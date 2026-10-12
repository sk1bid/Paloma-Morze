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
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#define SLEEP(ms) usleep((ms) * 1000)
#endif

#include "morse_audio.hpp"
#include <thread>
#include <iostream>
#include <mutex>
#include <atomic>
#include <fstream>
#include <cstdarg>

using MorseState = morse::Engine;
static std::mutex outputMutex;
static void emit_audio(const std::string& line) {
  std::lock_guard<std::mutex> lock(outputMutex);
  std::cout << line << std::endl;
}
static int log_printf(const char* format, ...) {
  char buffer[2048];va_list args;va_start(args,format);int n=vsnprintf(buffer,sizeof(buffer),format,args);va_end(args);
  std::lock_guard<std::mutex> lock(outputMutex);fputs(buffer,stdout);fflush(stdout);return n;
}
#define printf log_printf
void key_press(MorseState& state) { state.hardware = true; }
void key_release(MorseState& state) { state.hardware = false; }
void data_callback(ma_device *device, void *output, const void *, ma_uint32 frames) {
  static_cast<MorseState*>(device->pUserData)->render(static_cast<float*>(output), frames);
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
long long get_time_ms() { return GetTickCount(); }
#endif

bool process_command(const std::string& line, MorseState& state) {
  uint32_t requestId=0;
  try {
    std::istringstream in(line);std::string verb;in>>verb;
    if(verb=="P") {
      morse::Settings settings;int square,quality;std::string patterns;
      if(!(in>>requestId>>settings.speed>>settings.period>>settings.ratio>>settings.pause>>settings.front>>square>>quality>>settings.spacing>>patterns))
        throw std::runtime_error("invalid-play-command");
      settings.square=square!=0;settings.original=quality!=0;
      std::string extra;if(in>>extra)throw std::runtime_error("invalid-play-command");
      if(!state.submit(morse::makePlan(requestId,settings,patterns,state.rate)))throw std::runtime_error("audio-queue-full");
    } else if(verb=="STOP") {in>>requestId;state.stop(requestId);}
    else if(verb=="RESET") {state.stop();state.local=false;state.remote=false;state.muted=false;state.clearNotice();}
    else if(verb=="K") {
      std::string source;int held;if(!(in>>source>>held)||(held!=0&&held!=1))throw std::runtime_error("invalid-key-command");
      if(source=="remote")state.remote=held;else if(source=="local")state.local=held;else throw std::runtime_error("invalid-key-source");
    } else if(verb=="S") {
      double frequency,volume;int front,waveform,quality;
      if(!(in>>frequency>>volume>>front>>waveform>>quality)||!std::isfinite(frequency)||!std::isfinite(volume)||frequency<200||frequency>2000||volume<0||volume>100||front<0||front>12)
        throw std::runtime_error("invalid-settings");
      state.period=std::max(8,std::min(38,int(std::round(morse::ReferenceRate/frequency))));
      state.volume=float(volume/100);state.front=front;state.square=waveform!=0;state.original=quality!=0;
    } else if(verb=="N") {int connected;if(in>>connected)state.notify(connected!=0);}
    else if(line.size()>1) {
      double n=std::stod(line.substr(1));if(!std::isfinite(n))throw std::runtime_error("invalid-number");
      if(line[0]=='F'&&n>=200&&n<=2000)state.period=std::max(8,std::min(38,int(std::round(morse::ReferenceRate/n))));
      else if(line[0]=='V'&&n>=0&&n<=100)state.volume=float(n/100);
      else if(line[0]=='A'&&n>=0&&n<=12)state.front=int(n);
      else if(line[0]=='W')state.square=n!=0;
      else if(line[0]=='M')state.muted=n!=0;
      else throw std::runtime_error("invalid-command");
    } else throw std::runtime_error("invalid-command");
    return true;
  } catch(const std::exception& e) {
    emit_audio("AUDIO ERROR "+std::to_string(requestId)+" "+e.what());return false;
  }
}
void report_events(MorseState& state) {
  morse::Event e;
  while(state.poll(e)) {
    const char* name=e.type==morse::EventType::Start?"START":e.type==morse::EventType::Char?"CHAR":e.type==morse::EventType::Pulse?"PULSE":"DONE";
    emit_audio(std::string("AUDIO ")+name+" "+std::to_string(e.id)+" "+std::to_string(e.value));
  }
}

#ifndef TEST_RUNNER
int main(int argc, char** argv) {
  MorseState state(48000);
  std::string testMode = "";


  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg == "-h" || arg == "--help") {
      printf("Paloma Morse Engine (CLI Mode)\n");
      printf("Usage: morze_app [opts]\n");
      printf("  --freq <Hz>       Set base frequency (200-2000 Hz)\n");
      printf("  --vol <0-100>     Set max volume (0-100)\n");
      printf("  --help            Show this help message\n\n");
      return 0;
    } else if (arg == "--freq" || arg == "-f") {
      if (i + 1 < argc) {
        int f = atoi(argv[++i]);
        if (f >= 200 && f <= 2000) state.period = std::max(8,std::min(38,int(std::round(11025.0/f))));
      }
    } else if (arg == "--vol" || arg == "-v") {
      if (i + 1 < argc) {
        int v = atoi(argv[++i]);
        if (v >= 0 && v <= 100) state.volume = v / 100.0f;
      }
    } else if (arg == "--test-mode") {
      if (i + 1 < argc) testMode = argv[++i];
    }
  }


  ma_device_config config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_f32;
  config.playback.channels = 1;
  config.sampleRate = (ma_uint32)state.rate;
  config.periodSizeInFrames = 256;
  config.dataCallback = data_callback;
  config.pUserData = &state;

  ma_device device;
  if (testMode.empty()) {
    if (ma_device_init(NULL, &config, &device) != MA_SUCCESS) {
      printf("[Error] Failed to initialize playback device.\n");
      return -1;
    }
    if (ma_device_start(&device) != MA_SUCCESS) {
      printf("[Error] Failed to start playback device.\n");
      ma_device_uninit(&device);
      return -1;
    }
  }

  printf("[Engine] Cross-platform engine started. Freq: %.0fHz, Vol: %.0f%%\n", 11025.0/state.period.load(), state.volume.load() * 100);
  if (!testMode.empty()) printf("[Engine] Running in TEST MODE: %s\n", testMode.c_str());
  fflush(stdout);

  int fd = -1;
#ifdef _WIN32
  HANDLE hComm = INVALID_HANDLE_VALUE;
  long long lastDataTime = 0;
#endif
  std::string connectedPort = "";
  time_t lastHealthCheck = 0;
  char buf[1];
  std::atomic<bool> running{true};
  emit_audio("AUDIO READY 1 "+std::to_string(state.rate));
  // Commands remain responsive even while a USB handshake is waiting.
  std::thread reader([&] {
    std::string line;
    while(std::getline(std::cin,line)) {
      if(line.size()<=30000)process_command(line,state);
      else emit_audio("AUDIO ERROR 0 command-too-large");
    }
    state.emergencyStop=true;running=false;
  });
  std::thread reporter([&] {
    std::vector<float> silent(256);
    while(running) {
      if(!testMode.empty())state.render(silent.data(),silent.size());
      report_events(state);SLEEP(4);
    }
  });

  while (running) {
    if (!testMode.empty()) {
      if (testMode == "auth_ok" && connectedPort.empty()) {
        connectedPort = "MOCK_PORT";
        printf("[Engine] Connected to %s (Auth OK!)\n", connectedPort.c_str());
        fflush(stdout);
      } else if (testMode == "auth_fail" && connectedPort.empty()) {
        // printf("[Engine] Ignored MOCK_PORT (no PALOMA response)\n");
        fflush(stdout);
        SLEEP(2000);
      }
    }

#ifndef _WIN32
    if (fd == -1 && testMode.empty()) {

      std::vector<std::string> ports = findAvailablePorts();
      for (const auto &port : ports) {
            long long probe_start = get_time_ms();
            int test_fd = open(port.c_str(), O_RDWR | O_NOCTTY | O_NONBLOCK);
            if (test_fd != -1) {
              SLEEP(1000); // Даем FTDI/Arduino больше времени продышаться (особенно важно для Linux ftdi_sio)
              
              // Управление DTR/RTS для пробуждения Arduino
              int status;
              ioctl(test_fd, TIOCMGET, &status);
              status |= TIOCM_DTR;
              status |= TIOCM_RTS;
              ioctl(test_fd, TIOCMSET, &status);
              
              struct termios options;
              tcgetattr(test_fd, &options);
              cfsetispeed(&options, B115200);
              cfsetospeed(&options, B115200);
              options.c_cflag |= (CLOCAL | CREAD | CS8);
              options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
              options.c_iflag &= ~(IXON | IXOFF | IXANY);
              options.c_oflag &= ~OPOST;
              tcsetattr(test_fd, TCSANOW, &options);
              tcflush(test_fd, TCIOFLUSH);
              SLEEP(500); // Еще немного на стабилизацию после tcsetattr
              tcflush(test_fd, TCIFLUSH);
              
              // --- РУКОПОЖАТИЕ (СВОЙ-ЧУЖОЙ) ТЕРПЕЛИВОЕ ---
              long long hs_start_time = get_time_ms();
              bool handshake_ok = false;
              std::string hs_str = "";
              long long last_send = 0;

              // Даем плате 2.5 секунды на ответ (важно для медленных загрузчиков)
              while (get_time_ms() - hs_start_time < 2500) {
                long long now = get_time_ms();
                if (now - last_send > 200) {
                  write(test_fd, "?\n", 2);
                  last_send = now;
                }

                char hc;
                int r = read(test_fd, &hc, 1);
                if (r > 0) {
                  hs_str += hc;
                  // Проверка 1: Явное слово-пароль
                  if (hs_str.find("PALOMA") != std::string::npos) {
                    handshake_ok = true;
                    break;
                  }
                  // Проверка 2: Ленивая аутентификация (если пошли данные 1/0)
                  if (hs_str.find('1') != std::string::npos || hs_str.find('0') != std::string::npos) {
                    printf("[Engine] Auth OK via pulse data for %s\n", port.c_str());
                    handshake_ok = true;
                    break;
                  }
                } else {
                  SLEEP(10);
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
        } else {
            if (errno == EACCES) {
                static bool perm_warned = false;
                if (!perm_warned) {
                    printf("ERROR:EACCES (Permission denied for %s)\n", port.c_str());
                    fflush(stdout);
                    perm_warned = true;
                }
            }
        }
      }
      if (fd == -1)
        SLEEP(500);
    }

    // Health check
    if (fd != -1) {
      time_t now = time(NULL);
      if (now - lastHealthCheck >= 2) {
        lastHealthCheck = now;
        if (access(connectedPort.c_str(), F_OK) != 0) {
          close(fd);
          fd = -1;
          key_release(state);
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
          key_press(state);
          printf("1\n");
        } else if (buf[0] == '0') {
          key_release(state);
          printf("0\n");
        }
        fflush(stdout);
      } else if (n == 0 || (n < 0 && errno != EAGAIN)) {
        close(fd);
        fd = -1;
        key_release(state);
        printf("[Engine] Disconnected. Reconnecting...\n");
        fflush(stdout);
      }
    }
#else
    if (hComm == INVALID_HANDLE_VALUE && testMode.empty()) {

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
            lastDataTime = get_time_ms();
            printf("[Engine] Connected to %s (Auth OK!)\n", port.c_str());
            fflush(stdout);
            break;
          } else {
            CloseHandle(test_h);
            // printf("[Engine] Ignored %s (no PALOMA response)\n", port.c_str());
            fflush(stdout);
          }
        }
      }
      if (hComm == INVALID_HANDLE_VALUE)
        SLEEP(2000);
    }

    if (hComm != INVALID_HANDLE_VALUE) {
      // Health check: verify COM port is still alive
      time_t now = time(NULL);
      if (now - lastHealthCheck >= 2) {
        lastHealthCheck = now;
        DWORD errors = 0;
        COMSTAT comStat;
        if (!ClearCommError(hComm, &errors, &comStat) || errors != 0) {
          CloseHandle(hComm);
          hComm = INVALID_HANDLE_VALUE;
          key_release(state);
          connectedPort.clear();
          printf("[Engine] Port error detected. Reconnecting...\n");
          fflush(stdout);
          continue;
        }
      }

      char bufWIN[1];
      DWORD bytes_read;
      if (ReadFile(hComm, bufWIN, 1, &bytes_read, NULL)) {
        if (bytes_read > 0) {
          lastDataTime = get_time_ms();
          if (bufWIN[0] == '1') {
            key_press(state);
            printf("1\n");
          } else if (bufWIN[0] == '0') {
            key_release(state);
            printf("0\n");
          }
          fflush(stdout);
        }
      } else {
        CloseHandle(hComm);
        hComm = INVALID_HANDLE_VALUE;
        key_release(state);
        connectedPort.clear();
        lastDataTime = 0;
        printf("[Engine] Disconnected. Reconnecting...\n");
        fflush(stdout);
      }
    }
#endif

    SLEEP(1);
  }

  reader.join();reporter.join();
  if(testMode.empty())ma_device_uninit(&device);
  return 0;
}
#endif
