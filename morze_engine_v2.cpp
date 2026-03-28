#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <time.h>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#define SLEEP(ms) Sleep(ms)
#else
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>
#define SLEEP(ms) usleep((ms) * 1000)
#endif

// --- КРОСС-ПЛАТФОРМЕННЫЙ ЗВУКОВОЙ ДВИЖОК ---
// Репликация 1:1 логики из macOS AVFoundation версии

struct MorseState {
  double phase;
  double frequency;
  float currentVolume;
  float targetVolume;
  float maxVolume;
  double sampleRate;
};

void data_callback(ma_device *pDevice, void *pOutput, const void *pInput,
                   ma_uint32 frameCount) {
  MorseState *pState = (MorseState *)pDevice->pUserData;
  float *out = (float *)pOutput;

  float target = pState->targetVolume;
  float current = pState->currentVolume;
  double freq = pState->frequency;
  double phase = pState->phase;
  double sr = pState->sampleRate;

  for (ma_uint32 i = 0; i < frameCount; ++i) {
    if (current < target) {
      current += 0.001f;
      if (current > target)
        current = target;
    } else if (current > target) {
      current -= 0.001f;
      if (current < target)
        current = target;
    }

    // Чистая синусоида
    out[i] = (float)sin(phase * 2.0 * M_PI) * current;

    // Накопление фазы
    phase += freq / sr;
    if (phase >= 1.0)
      phase -= 1.0;
  }

  pState->currentVolume = current;
  pState->phase = phase;

  (void)pInput;
}

// Поиск всех портов вместо одного последнего (POSIX версия)
#ifndef _WIN32
#include <algorithm>
#include <sys/time.h>

struct PortInfo {
  std::string name;
  time_t mtime;
};

std::vector<std::string> findAvailablePorts() {
  std::vector<PortInfo> pinfo;
  DIR *dir = opendir("/dev");
  if (!dir)
    return std::vector<std::string>();
  struct dirent *entry;
  while ((entry = readdir(dir)) != NULL) {
    std::string name = entry->d_name;
    // Ищем вообще все USB-модемы или serial устройства
    if (name.find("cu.usbmodem") != std::string::npos ||
        name.find("ttyACM") != std::string::npos ||
        name.find("ttyUSB") != std::string::npos ||
        name.find("cu.wchusb") != std::string::npos ||
        name.find("cu.usbserial") != std::string::npos) {
      std::string path = "/dev/" + name;
      struct stat st;
      if (stat(path.c_str(), &st) == 0) {
        pinfo.push_back({path, st.st_mtime});
      }
    }
  }
  closedir(dir);
  // Сортировка по времени модификации (самые новые первыми)
  std::sort(
      pinfo.begin(), pinfo.end(),
      [](const PortInfo &a, const PortInfo &b) { return a.mtime > b.mtime; });
  std::vector<std::string> ports;
  for (auto &p : pinfo)
    ports.push_back(p.name);
  return ports;
}

long long get_time_ms() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (long long)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}
#else
std::vector<std::string> findAvailablePorts() {
  std::vector<std::string> ports;
  for (int i = 1; i <= 99; ++i) {
    char port_name[32];
    sprintf(port_name, "\\\\.\\COM%d", i);
    HANDLE hComm = CreateFileA(port_name, GENERIC_READ | GENERIC_WRITE, 0, 0,
                               OPEN_EXISTING, 0, 0);
    if (hComm != INVALID_HANDLE_VALUE) {
      CloseHandle(hComm);
      char short_name[16];
      sprintf(short_name, "COM%d", i);
      ports.push_back(short_name);
    }
  }
  return ports;
}
long long get_time_ms() { return GetTickCount64(); }
#endif

int main() {
  MorseState state;
  state.phase = 0.0;
  state.frequency = 700.0;
  state.currentVolume = 0.0f;
  state.targetVolume = 0.0f;
  state.maxVolume = 0.5f;
  state.sampleRate = 44100.0;

  ma_device_config config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_f32;
  config.playback.channels = 1;
  config.sampleRate = (ma_uint32)state.sampleRate;
  config.dataCallback = data_callback;
  config.pUserData = &state;

  ma_device device;
  if (ma_device_init(NULL, &config, &device) != MA_SUCCESS) {
    printf("[Error] Failed to initialize playback device.\n");
    return -1;
  }

  if (ma_device_start(&device) != MA_SUCCESS) {
    printf("[Error] Failed to start playback device.\n");
    ma_device_uninit(&device);
    return -1;
  }

  printf("[Engine] Cross-platform engine started (miniaudio).\n");
  fflush(stdout);

  int fd = -1;
#ifdef _WIN32
  HANDLE hComm = INVALID_HANDLE_VALUE;
#endif
  std::string connectedPort = "";
  time_t lastHealthCheck = 0;
  char buf[1];
  char stdin_buf[16];
  int stdin_pos = 0;

#ifndef _WIN32
  // Non-blocking stdin
  int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
  fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
#endif

  while (true) {
#ifndef _WIN32
    if (fd == -1) {
      std::vector<std::string> ports = findAvailablePorts();
      for (const auto &port : ports) {
        int test_fd = open(port.c_str(), O_RDWR | O_NOCTTY | O_NONBLOCK);
        if (test_fd != -1) {
          SLEEP(100);
          struct termios options;
          memset(&options, 0, sizeof(options));
          tcgetattr(test_fd, &options);
          cfsetispeed(&options, B115200);
          cfsetospeed(&options, B115200);
          options.c_cflag |= (CLOCAL | CREAD | CS8);
          options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
          options.c_iflag &= ~(IXON | IXOFF | IXANY);
          options.c_oflag &= ~OPOST;
          tcsetattr(test_fd, TCSANOW, &options);
          tcflush(test_fd, TCIOFLUSH);
          SLEEP(50);

          // --- РУКОПОЖАТИЕ (СВОЙ-ЧУЖОЙ) БЫСТРОЕ ---
          long long start_time = get_time_ms();
          bool handshake_ok = false;
          std::string hs_str = "";
          long long last_send = 0;

          while (get_time_ms() - start_time < 3000) {
            long long now = get_time_ms();
            if (now - last_send > 200) {
              write(test_fd, "?\n", 2);
              last_send = now;
            }

            char hc;
            int r = read(test_fd, &hc, 1);
            if (r > 0) {
              hs_str += hc;
              if (hs_str.find("PALOMA") != std::string::npos) {
                handshake_ok = true;
                break;
              }
              if (hs_str.length() > 500)
                hs_str = hs_str.substr(250);
            } else {
              SLEEP(5);
            }
          }

          if (handshake_ok) {
            fd = test_fd;
            connectedPort = port;
            lastHealthCheck = time(NULL);
            printf("[Engine] Connected to %s (Auth OK!)\n", port.c_str());
            fflush(stdout);
            break;
          } else {
            close(test_fd);
            printf("[Engine] Ignored %s (no PALOMA response)\n", port.c_str());
            fflush(stdout);
          }
        }
      }
      if (fd == -1)
        SLEEP(250);
    }

    // Health check
    if (fd != -1) {
      time_t now = time(NULL);
      if (now - lastHealthCheck >= 2) {
        lastHealthCheck = now;
        if (access(connectedPort.c_str(), F_OK) != 0) {
          close(fd);
          fd = -1;
          state.targetVolume = 0.0f;
          connectedPort.clear();
          printf("[Engine] Port lost. Reconnecting...\n");
          fflush(stdout);
          continue;
        }
      }

      // Read Arduino
      ssize_t n = read(fd, buf, 1);
      if (n > 0) {
        if (buf[0] == '1') {
          state.targetVolume = state.maxVolume;
          printf("1\n");
        } else if (buf[0] == '0') {
          state.targetVolume = 0.0f;
          printf("0\n");
        }
        fflush(stdout);
      } else if (n == 0 || (n < 0 && errno != EAGAIN)) {
        close(fd);
        fd = -1;
        state.targetVolume = 0.0f;
        printf("[Engine] Disconnected. Reconnecting...\n");
        fflush(stdout);
      }
    }
#else
    if (hComm == INVALID_HANDLE_VALUE) {
      std::vector<std::string> ports = findAvailablePorts();
      for (const auto &port : ports) {
        char port_name[32];
        sprintf(port_name, "\\\\.\\%s", port.c_str());
        HANDLE test_h = CreateFileA(port_name, GENERIC_READ | GENERIC_WRITE, 0, 0,
                                    OPEN_EXISTING, 0, 0);
        if (test_h != INVALID_HANDLE_VALUE) {
          DCB dcbSerialParams = {0};
          dcbSerialParams.DCBlength = sizeof(dcbSerialParams);
          if (GetCommState(test_h, &dcbSerialParams)) {
            dcbSerialParams.BaudRate = CBR_115200;
            dcbSerialParams.ByteSize = 8;
            dcbSerialParams.StopBits = ONESTOPBIT;
            dcbSerialParams.Parity = NOPARITY;
            dcbSerialParams.fDtrControl = DTR_CONTROL_ENABLE;
            SetCommState(test_h, &dcbSerialParams);
          }
          COMMTIMEOUTS timeouts = {0};
          timeouts.ReadIntervalTimeout = MAXDWORD;
          timeouts.ReadTotalTimeoutConstant = 0;
          timeouts.ReadTotalTimeoutMultiplier = 0;
          SetCommTimeouts(test_h, &timeouts);

          PurgeComm(test_h, PURGE_RXCLEAR | PURGE_TXCLEAR);
          SLEEP(50);

          long long start_time = get_time_ms();
          bool handshake_ok = false;
          std::string hs_str = "";
          long long last_send = 0;

          while (get_time_ms() - start_time < 3000) {
            long long now = get_time_ms();
            if (now - last_send > 200) {
              DWORD bytes_written;
              WriteFile(test_h, "?\n", 2, &bytes_written, NULL);
              last_send = now;
            }

            char hc;
            DWORD bytes_read;
            if (ReadFile(test_h, &hc, 1, &bytes_read, NULL) && bytes_read > 0) {
              hs_str += hc;
              if (hs_str.find("PALOMA") != std::string::npos) {
                handshake_ok = true;
                break;
              }
              if (hs_str.length() > 500)
                hs_str = hs_str.substr(250);
            } else {
              SLEEP(5);
            }
          }

          if (handshake_ok) {
            hComm = test_h;
            connectedPort = port;
            lastHealthCheck = time(NULL);
            printf("[Engine] Connected to %s (Auth OK!)\n", port.c_str());
            fflush(stdout);
            break;
          } else {
            CloseHandle(test_h);
            printf("[Engine] Ignored %s (no PALOMA response)\n", port.c_str());
            fflush(stdout);
          }
        }
      }
      if (hComm == INVALID_HANDLE_VALUE)
        SLEEP(250);
    }

    if (hComm != INVALID_HANDLE_VALUE) {
      time_t now = time(NULL);
      if (now - lastHealthCheck >= 2) {
        lastHealthCheck = now;
      }

      char bufWIN[1];
      DWORD bytes_read;
      if (ReadFile(hComm, bufWIN, 1, &bytes_read, NULL)) {
        if (bytes_read > 0) {
          if (bufWIN[0] == '1') {
            state.targetVolume = state.maxVolume;
            printf("1\n");
          } else if (bufWIN[0] == '0') {
            state.targetVolume = 0.0f;
            printf("0\n");
          }
          fflush(stdout);
        }
      } else {
        CloseHandle(hComm);
        hComm = INVALID_HANDLE_VALUE;
        state.targetVolume = 0.0f;
        printf("[Engine] Disconnected. Reconnecting...\n");
        fflush(stdout);
      }
    }
#endif

    // STDIN parsing (Cross-platform friendly)
#ifndef _WIN32
    char c;
    if (read(STDIN_FILENO, &c, 1) > 0) {
      if (c == '\n') {
        stdin_buf[stdin_pos] = '\0';
        if (stdin_buf[0] == 'F') {
          int f = atoi(stdin_buf + 1);
          if (f >= 200 && f <= 2000)
            state.frequency = (double)f;
        } else if (stdin_buf[0] == 'V') {
          int v = atoi(stdin_buf + 1);
          if (v >= 0 && v <= 100) {
            state.maxVolume = v / 100.0f;
            if (state.targetVolume > 0.0f)
              state.targetVolume = state.maxVolume;
          }
        }
        stdin_pos = 0;
      } else if (stdin_pos < 15) {
        stdin_buf[stdin_pos++] = c;
      }
    }
#else
    DWORD bytesAvail = 0;
    if (PeekNamedPipe(GetStdHandle(STD_INPUT_HANDLE), NULL, 0, NULL, &bytesAvail, NULL) && bytesAvail > 0) {
      char cPos;
      DWORD bytesRead;
      if (ReadFile(GetStdHandle(STD_INPUT_HANDLE), &cPos, 1, &bytesRead, NULL) && bytesRead > 0) {
        if (cPos == '\n') {
          stdin_buf[stdin_pos] = '\0';
          if (stdin_buf[0] == 'F') {
            int f = atoi(stdin_buf + 1);
            if (f >= 200 && f <= 2000)
              state.frequency = (double)f;
          } else if (stdin_buf[0] == 'V') {
            int v = atoi(stdin_buf + 1);
            if (v >= 0 && v <= 100) {
              state.maxVolume = v / 100.0f;
              if (state.targetVolume > 0.0f)
                state.targetVolume = state.maxVolume;
            }
          }
          stdin_pos = 0;
        } else if (stdin_pos < 15) {
          stdin_buf[stdin_pos++] = cPos;
        }
      }
    }
#endif
    SLEEP(1);
  }

  ma_device_uninit(&device);
  return 0;
}
