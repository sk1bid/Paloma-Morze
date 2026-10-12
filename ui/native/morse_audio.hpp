#pragma once
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace morse {
constexpr double Pi = 3.14159265358979323846;
constexpr int ReferenceRate = 11025;
inline int roundEven(double x) {
    double lower = std::floor(x), fraction = x - lower;
    return static_cast<int>(fraction == 0.5 ? lower + (static_cast<int64_t>(lower) & 1) : std::floor(x + 0.5));
}
struct Settings {
    int speed=50, period=23, ratio=30, pause=30, front=6;
    bool square=false, original=false;
    int spacing=0; // 0=text, 1=learning, 2=repeat
    void validate() const {
        if(speed<30 || speed>150 || speed%5 || period<8 || period>38 || ratio<20 || ratio>45 ||
           pause<10 || pause>60 || front<0 || front>12 || spacing<0 || spacing>2)
            throw std::runtime_error("invalid-settings");
    }
    int dot() const { return roundEven(66120.0/speed); }
    int dash() const { return roundEven(dot()*ratio/10.0); }
    int edge() const { return roundEven((13-front)*ReferenceRate/2000.0); }
    int gap(bool group) const {
        static constexpr int calibration[]={188,161,140,124,111,93,92,91,70,65,60,62,58,43,56,45,39,37,41,33,41,34,25,23,31};
        int c=calibration[speed/5-6], mul=group?3:1;
        int ms=spacing==1 ? (group?1500:500) : spacing==2 ? mul*2*c*pause/10
            : static_cast<int>(mul*pause*dot()*1000.0/110250.0)+c;
        return dot()+roundEven(ms*ReferenceRate/1000.0);
    }
};
inline uint8_t legacySample(int i, int length, const Settings& s) {
    const int edge=s.edge();
    double envelope=i<edge ? i/double(edge) : i>=length-edge ? (length-i)/double(edge) : 1;
    double amplitude=s.square && i>=edge && i<length-edge ? 120 : 127;
    int value=128+roundEven(std::sin(2*Pi*i/s.period)*amplitude*envelope);
    return static_cast<uint8_t>(s.square ? (value>128?248:8) : value);
}
struct Pulse { uint64_t start,end; bool dash; };
struct Character { uint64_t frame; int index; };
struct Plan {
    uint32_t id=0;
    Settings settings;
    int rate=48000;
    uint64_t frames=0;
    std::vector<Pulse> pulses;
    std::vector<Character> characters;
    std::vector<uint8_t> dot, dash;
};
inline Plan makePlan(uint32_t id,const Settings& s,const std::string& patterns,int rate=48000) {
    s.validate();
    if(rate<8000 || rate>192000 || patterns.size()>20000) throw std::runtime_error("sequence-too-large");
    Plan plan; plan.id=id;plan.settings=s;plan.rate=rate;
    auto frame=[rate](uint64_t f){return static_cast<uint64_t>(roundEven(f*double(rate)/ReferenceRate));};
    uint64_t cursor=0;bool have=false,group=false;int tokenIndex=0;
    std::istringstream input(patterns);std::string token;
    while(std::getline(input,token,'|')) {
        if(token=="/") {group=true;++tokenIndex;continue;}
        if(token.empty() || token.find_first_not_of(".-,")!=std::string::npos || token.front()==',' || token.back()==',' || token.find(",,")!=std::string::npos)
            throw std::runtime_error("invalid-pattern");
        if(have)cursor+=s.gap(group);
        group=false;plan.characters.push_back({frame(cursor),tokenIndex++});
        bool first=true;
        for(char c:token) {
            if(c==',') {cursor+=s.gap(false);first=true;continue;}
            if(!first)cursor+=s.dot();
            int count=c=='-'?s.dash():s.dot();
            plan.pulses.push_back({frame(cursor),frame(cursor+count),c=='-'});
            cursor+=count;first=false;
        }
        have=true;
        if(cursor>uint64_t(ReferenceRate)*3600 || plan.pulses.size()>20000)throw std::runtime_error("sequence-too-large");
    }
    if(!have)throw std::runtime_error("empty-sequence");
    plan.frames=frame(cursor+s.dot());
    plan.dot.resize(s.dot());plan.dash.resize(s.dash());
    for(int i=0;i<s.dot();++i)plan.dot[i]=legacySample(i,s.dot(),s);
    for(int i=0;i<s.dash();++i)plan.dash[i]=legacySample(i,s.dash(),s);
    return plan;
}
inline float carrier(double phase,const Settings& s,int rate) {
    if(!s.square)return float((127.0/128)*std::sin(2*Pi*phase));
    // Fixed, band-limited odd harmonics; no allocations in the audio callback.
    int highest=std::min(15,int(0.45*rate/(ReferenceRate/double(s.period))));
    double sum=0;
    for(int h=1;h<=highest;h+=2)sum+=std::sin(2*Pi*h*phase)/h;
    return float(std::max(-120.0/128,std::min(120.0/128,sum*0.8)));
}
inline float sample(const Plan& p,const Pulse& pulse,uint64_t position) {
    uint64_t i=position-pulse.start, length=pulse.end-pulse.start;
    if(p.settings.original) {
        const auto& data=pulse.dash?p.dash:p.dot;
        double x=i*double(ReferenceRate)/p.rate;
        size_t a=std::min(size_t(x),data.size()-1),b=std::min(a+1,data.size()-1);
        return float(((data[a]-128)*(1-(x-a))+(data[b]-128)*(x-a))/128.0);
    }
    double edge=p.settings.edge()*double(p.rate)/ReferenceRate;
    double envelope=std::min(1.0,std::min(i/edge,(length-1-i)/edge));
    return carrier((ReferenceRate/double(p.settings.period))*i/p.rate,p.settings,p.rate)*float(envelope);
}
// Bounded single-producer/single-consumer queues; the audio callback never waits.
template<class T,size_t N> class Queue {
    std::array<T,N> values{};
    std::atomic<size_t> write{0},read{0};
public:
    bool push(const T& value) {
        size_t w=write.load(std::memory_order_relaxed),next=(w+1)%N;
        if(next==read.load(std::memory_order_acquire))return false;
        values[w]=value;write.store(next,std::memory_order_release);return true;
    }
    bool pop(T& value) {
        size_t r=read.load(std::memory_order_relaxed);
        if(r==write.load(std::memory_order_acquire))return false;
        value=values[r];read.store((r+1)%N,std::memory_order_release);return true;
    }
};
enum class EventType { Start,Char,Pulse,Done };
struct Event { EventType type;uint32_t id;uint64_t value; };
struct Command { Plan* plan=nullptr;uint32_t stopId=0; };
class Engine {
    Queue<Command,128> commands;
    Queue<Event,8192> events;
    std::mutex ownershipMutex; // Used only by command/event threads, never render().
    std::unordered_map<uint32_t,std::unique_ptr<Plan>> ownership;
    Plan* active=nullptr;
    uint64_t position=0;size_t pulseIndex=0,charIndex=0;bool pulseOn=false;
    float envelope=0;double phase=0;
    int notification=0;uint64_t notificationFrame=0;
    std::atomic<int> requestedNotification{0};
    void done(bool cancelled) {
        if(!active)return;
        uint32_t id=active->id;active=nullptr;pulseOn=false;
        events.push({EventType::Done,id,cancelled?1u:0u});
    }
public:
    const int rate;
    std::atomic<int> period{23},front{6};
    std::atomic<bool> square{false},original{false},hardware{false},local{false},remote{false},muted{false};
    std::atomic<float> volume{0.5f};
    std::atomic<bool> emergencyStop{false};
    explicit Engine(int sampleRate=48000):rate(sampleRate){}
    bool submit(Plan plan) {
        auto value=std::unique_ptr<Plan>(new Plan(std::move(plan)));auto* pointer=value.get();
        std::lock_guard<std::mutex> lock(ownershipMutex);
        if(ownership.count(pointer->id) || ownership.size()>=64)return false;
        ownership[pointer->id]=std::move(value);
        if(commands.push({pointer,0}))return true;
        ownership.erase(pointer->id);return false;
    }
    void stop(uint32_t id=0) {if(!commands.push({nullptr,id}))emergencyStop=true;}
    void clearNotice() {requestedNotification=-1;}
    void notify(bool connected) {requestedNotification=connected?1:2;}
    bool poll(Event& event) {
        if(!events.pop(event))return false;
        if(event.type==EventType::Done) {std::lock_guard<std::mutex> lock(ownershipMutex);ownership.erase(event.id);}
        return true;
    }
    void render(float* out,size_t count) {
        Command command;
        while(commands.pop(command)) {
            if(command.plan) {
                done(true);active=command.plan;position=0;pulseIndex=charIndex=0;pulseOn=false;
                events.push({EventType::Start,active->id,active->frames});
            } else if(!command.stopId || (active && active->id==command.stopId))done(true);
        }
        if(emergencyStop.exchange(false)){done(true);local=false;remote=false;}
        Settings live;live.period=period.load();live.front=front.load();live.square=square.load();live.original=original.load();
        bool held=remote.load() || local.load() || (hardware.load()&&!muted.load());
        if(held)done(true); // Manual/remote CW preempts lessons; never mix two Morse tones.
        int notice=requestedNotification.exchange(0);
        if(notice<0)notification=0;
        else if(notice&&!held&&!active){notification=notice;notificationFrame=0;phase=0;}
        if(held||active)notification=0;
        float gain=std::max(0.0f,std::min(1.0f,volume.load()));
        double edge=std::max(1.0,live.edge()*double(rate)/ReferenceRate);
        for(size_t j=0;j<count;++j) {
            float value=0;
            if(held || envelope>0) {
                if(held && envelope==0)phase=0;
                envelope=std::max(0.0f,std::min(1.0f,envelope+float((held?1:-1)/edge)));
                if(live.original){int n=roundEven(127*std::sin(2*Pi*phase));value=float(live.square?(n>0?120:-120):n)/128*envelope;}
                else value=carrier(phase,live,rate)*envelope;
                phase+=ReferenceRate/double(live.period)/rate;phase-=std::floor(phase);
            } else if(active) {
                while(charIndex<active->characters.size()&&active->characters[charIndex].frame<=position)
                    {events.push({EventType::Char,active->id,uint64_t(active->characters[charIndex++].index)});}
                while(pulseIndex<active->pulses.size()&&active->pulses[pulseIndex].end<=position){
                    if(pulseOn)events.push({EventType::Pulse,active->id,0});pulseOn=false;++pulseIndex;
                }
                if(pulseIndex<active->pulses.size()&&active->pulses[pulseIndex].start<=position){
                    const auto& p=active->pulses[pulseIndex];
                    if(!pulseOn){events.push({EventType::Pulse,active->id,p.dash?2u:1u});pulseOn=true;}
                    value=sample(*active,p,position);
                }
                if(++position>=active->frames)done(false);
            } else if(notification) {
                double t=notificationFrame/double(rate),duration=notification==1?0.2:0.25;
                double f=notification==1?523.25*std::pow(783.99/523.25,std::min(t/0.1,1.0)):392*std::pow(261.63/392,std::min(t/0.1,1.0));
                float env=float(std::max(0.0,std::min(t/0.02,(duration-t)/(duration-0.02))));
                value=0.2f*env*float(std::sin(2*Pi*phase));phase+=f/rate;phase-=std::floor(phase);
                if(++notificationFrame>=uint64_t(duration*rate))notification=0;
            }
            out[j]=value*gain;
        }
    }
};
} // namespace morse
