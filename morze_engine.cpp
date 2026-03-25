#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <iostream>
#include <termios.h>
#include <unistd.h>
#include <cmath>
#include <string>
#include <cctype>
#include <cstdlib>
#include <cerrno>
#include <cstring>

// --- ПРОФЕССИОНАЛЬНЫЙ ЗВУКОВОЙ ДВИЖОК (macOS) ---
@interface MorseOscillator : NSObject
@property (strong) AVAudioEngine *engine;
@property (strong) AVAudioSourceNode *sourceNode;
@property (assign) double frequency;
@property (assign) double phase;
@property (assign) float currentVolume;
@property (assign) float targetVolume;
@property (strong) dispatch_source_t timer;
@end

@implementation MorseOscillator {
    double _phase;
    double _sampleRate;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _engine = [[AVAudioEngine alloc] init];
        _frequency = 700.0;
        _sampleRate = 44100.0;
        _phase = 0.0;
        _currentVolume = 0.0f;
        _targetVolume = 0.0f;

        __weak MorseOscillator *weakSelf = self;
        _sourceNode = [[AVAudioSourceNode alloc] initWithRenderBlock:
            ^OSStatus(BOOL *silence, const AudioTimeStamp *timestamp, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
            float *outL = (float *)outputData->mBuffers[0].mData;
            float target = weakSelf.targetVolume;
            float current = weakSelf.currentVolume;
            
            for (AVAudioFrameCount i = 0; i < frameCount; i++) {
                // Smooth volume ramp (approx 5-10ms)
                if (current < target) {
                    current = fminf(current + 0.002f, target);
                } else if (current > target) {
                    current = fmaxf(current - 0.002f, target);
                }
                
                double val = sin(weakSelf.phase * 2.0 * M_PI);
                outL[i] = (float)val * current;
                
                weakSelf.phase += weakSelf.frequency / 44100.0;
                if (weakSelf.phase >= 1.0) weakSelf.phase -= 1.0;
            }
            weakSelf.currentVolume = current;
            return noErr;
        }];

        [_engine attachNode:_sourceNode];
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:_sampleRate channels:1];
        [_engine connect:_sourceNode to:_engine.mainMixerNode format:format];

        NSError *error;
        [_engine startAndReturnError:&error];

        // Listen for output device changes
        [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioEngineConfigurationChangeNotification
                                                          object:_engine
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            NSError *err;
            [weakSelf.engine startAndReturnError:&err];
            printf("[Engine] Configuration changed, restarted.\n");
            fflush(stdout);
        }];
    }
    return self;
}

- (double)phase { return _phase; }
- (void)setPhase:(double)p { _phase = p; }

- (void)start { self.targetVolume = 0.5f; }
- (void)stop { self.targetVolume = 0.0f; }
@end

#include <dirent.h>
#include <sys/stat.h>

std::string findPort() {
    DIR* dir = opendir("/dev");
    if (!dir) return "";
    struct dirent* entry;
    std::string bestPort;
    time_t bestTime = 0;
    while ((entry = readdir(dir)) != nullptr) {
        std::string name = entry->d_name;
        if (name.find("cu.usbmodem") != std::string::npos) {
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

int main() {
    @autoreleasepool {
        MorseOscillator *osc = [[MorseOscillator alloc] init];
        int fd = -1;
        
        char buf[1];
        char stdin_buf[16];
        int stdin_pos = 0;

        // Non-blocking stdin
        int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
        fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);

        while (true) {
            if (fd == -1) {
                std::string port = findPort();
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
                        usleep(100000); // Wait 100ms for hardware to stabilize
                        printf("[Engine] Connected to %s\n", port.c_str());
                        fflush(stdout);
                    }
                }
                if (fd == -1) usleep(1000000); // 1s wait
            }

            // Arduino -> UI & Sound
            if (fd != -1) {
                ssize_t n = read(fd, buf, 1);
                if (n > 0) {
                    if (buf[0] == '1') {
                        [osc start];
                        printf("1\n");
                        fflush(stdout);
                    } else if (buf[0] == '0') {
                        [osc stop];
                        printf("0\n");
                        fflush(stdout);
                    }
                } else if (n < 0 && errno != EAGAIN) {
                    // Actual error - port lost
                    close(fd);
                    fd = -1;
                    printf("[Engine] Connection lost (errno: %d). Retrying...\n", errno);
                    fflush(stdout);
                }
            }

            // UI -> Engine (Frequency)
            char c;
            if (read(STDIN_FILENO, &c, 1) > 0) {
                if (c == '\n') {
                    stdin_buf[stdin_pos] = '\0';
                    int f = atoi(stdin_buf);
                    if (f >= 200 && f <= 2000) osc.frequency = f;
                    stdin_pos = 0;
                } else if (isdigit(c) && stdin_pos < 15) {
                    stdin_buf[stdin_pos++] = c;
                }
            }
            usleep(1000); 
        }
    }
    return 0;
}