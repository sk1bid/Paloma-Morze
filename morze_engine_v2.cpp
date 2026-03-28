#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <time.h>
#include <vector>
#include <string>

#ifdef _WIN32
    #include <windows.h>
    #define SLEEP(ms) Sleep(ms)
#else
    #include <fcntl.h>
    #include <termios.h>
    #include <unistd.h>
    #include <dirent.h>
    #include <sys/stat.h>
    #include <errno.h>
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

void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    MorseState* pState = (MorseState*)pDevice->pUserData;
    float* out = (float*)pOutput;

    float target = pState->targetVolume;
    float current = pState->currentVolume;
    double freq = pState->frequency;
    double phase = pState->phase;
    double sr = pState->sampleRate;

    for (ma_uint32 i = 0; i < frameCount; ++i) {
        // Линейная огибающая (11.6мс при 44.1кГц)
        // 0.001f на сэмпл - точная копия из morze_engine.cpp
        if (current < target) {
            current += 0.001f;
            if (current > target) current = target;
        } else if (current > target) {
            current -= 0.001f;
            if (current < target) current = target;
        }

        // Чистая синусоида
        out[i] = (float)sin(phase * 2.0 * M_PI) * current;

        // Накопление фазы
        phase += freq / sr;
        if (phase >= 1.0) phase -= 1.0;
    }

    pState->currentVolume = current;
    pState->phase = phase;

    (void)pInput;
}

// Поиск порта (POSIX версия)
#ifndef _WIN32
std::string findBestPort() {
    std::string bestPort = "";
    time_t bestTime = 0;
    DIR* dir = opendir("/dev");
    if (!dir) return "";
    struct dirent* entry;
    while ((entry = readdir(dir)) != NULL) {
        std::string name = entry->d_name;
        if (name.find("cu.usbmodem") != std::string::npos || name.find("ttyACM") != std::string::npos) {
            std::string path = "/dev/" + name;
            struct stat st;
            if (stat(path.c_str(), &st) == 0) {
                if (st.st_mtime > bestTime) {
                    bestTime = st.st_mtime;
                    bestPort = path;
                }
            }
        }
    }
    closedir(dir);
    return bestPort;
}
#else
std::string findBestPort() {
    // В Windows обычно используется прямой выбор или перебор COM портов. 
    // Для совместимости возвращаем пустую строку или можно добавить перебор.
    return ""; 
}
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
    config.playback.format   = ma_format_f32;
    config.playback.channels = 1;
    config.sampleRate        = (ma_uint32)state.sampleRate;
    config.dataCallback      = data_callback;
    config.pUserData         = &state;

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
            std::string port = findBestPort();
            if (!port.empty()) {
                fd = open(port.c_str(), O_RDWR | O_NOCTTY | O_NONBLOCK);
                if (fd != -1) {
                    struct termios options;
                    memset(&options, 0, sizeof(options));
                    tcgetattr(fd, &options);
                    cfsetispeed(&options, B115200);
                    cfsetospeed(&options, B115200);
                    options.c_cflag |= (CLOCAL | CREAD | CS8);
                    options.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
                    options.c_iflag &= ~(IXON | IXOFF | IXANY);
                    options.c_oflag &= ~OPOST;
                    tcsetattr(fd, TCSANOW, &options);
                    SLEEP(100);
                    connectedPort = port;
                    lastHealthCheck = time(NULL);
                    printf("[Engine] Connected to %s\n", port.c_str());
                    fflush(stdout);
                }
            }
            if (fd == -1) SLEEP(1000);
        }

        // Health check
        if (fd != -1) {
            time_t now = time(NULL);
            if (now - lastHealthCheck >= 2) {
                lastHealthCheck = now;
                if (access(connectedPort.c_str(), F_OK) != 0) {
                    close(fd); fd = -1;
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
                if (buf[0] == '1') { state.targetVolume = state.maxVolume; printf("1\n"); }
                else if (buf[0] == '0') { state.targetVolume = 0.0f; printf("0\n"); }
                fflush(stdout);
            } else if (n == 0 || (n < 0 && errno != EAGAIN)) {
                close(fd); fd = -1;
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
                    if (f >= 200 && f <= 2000) state.frequency = (double)f;
                } else if (stdin_buf[0] == 'V') {
                    int v = atoi(stdin_buf + 1);
                    if (v >= 0 && v <= 100) {
                        state.maxVolume = v / 100.0f;
                        if (state.targetVolume > 0.0f) state.targetVolume = state.maxVolume;
                    }
                }
                stdin_pos = 0;
            } else if (stdin_pos < 15) {
                stdin_buf[stdin_pos++] = c;
            }
        }
#endif
        SLEEP(1);
    }

    ma_device_uninit(&device);
    return 0;
}
