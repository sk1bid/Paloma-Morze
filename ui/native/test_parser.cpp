#define TEST_RUNNER
#include "morze_engine_v2.cpp"
#include <cassert>
#include <iostream>
#include <fstream>
#include <iterator>

static std::vector<float> renderPlan(morse::Plan p) {
    morse::Engine engine(p.rate);engine.volume=1;
    const auto frames=p.frames;assert(engine.submit(std::move(p)));
    std::vector<float> result(frames);size_t pos=0;
    while(pos<frames){size_t count=std::min<size_t>(137,frames-pos);engine.render(result.data()+pos,count);pos+=count;morse::Event e;while(engine.poll(e)){};}
    return result;
}
int main(int argc,char**argv) {
    const std::string dir=argc>1?argv[1]:"ui/tests/fixtures/apak-2.12";
    morse::Settings s;s.original=true;
    const std::pair<const char*,const char*> cases[]={{"E","."},{"L",".-.."},{"V","...-"},{"A",".-"}};
    for(auto entry:cases){
        auto plan=morse::makePlan(1,s,entry.second,11025);auto pcm=renderPlan(plan);
        std::ifstream file(dir+"/"+entry.first+".pcm",std::ios::binary);assert(file.good());
        std::vector<uint8_t> golden((std::istreambuf_iterator<char>(file)),{});assert(golden.size()==pcm.size());
        for(size_t i=0;i<golden.size();i++)assert(pcm[i]==(int(golden[i])-128)/128.0f);
    }
    std::cout<<"4 captured APAK fixtures: byte-exact native rendering\n";
    s.original=false;
    auto text=morse::makePlan(2,s,".|.|/|.",11025);
    assert(text.pulses[1].start==7826 && text.pulses[2].start==23590 && text.frames==26234);
    s.spacing=1;auto lesson=morse::makePlan(3,s,".|.|/|.",11025);
    assert(lesson.pulses[1].start==8156 && lesson.pulses[2].start==27338);
    s.spacing=2;auto repeat=morse::makePlan(4,s,".|.",11025);assert(repeat.pulses[1].start==9987);
    s.spacing=0;
    assert(morse::roundEven(0.5)==0 && morse::roundEven(1.5)==2 && morse::roundEven(-1.5)==-2);
    auto q=morse::makePlan(5,s,".,.",48000),two=morse::makePlan(6,s,".|.",48000);assert(q.frames==two.frames);
    for(int rate:{44100,48000,96000}){
        auto p=morse::makePlan(7,s,".-|.|/|.-..",rate);auto clean=renderPlan(p);
        for(auto pulse:p.pulses){assert(clean[pulse.start]==0 && clean[pulse.end-1]==0);}
        for(float x:clean)assert(std::isfinite(x)&&std::abs(x)<=1);
        uint64_t end=0;for(auto pulse:p.pulses){for(uint64_t i=end;i<pulse.start;i++)assert(clean[i]==0);end=pulse.end;}
    }
    morse::Engine engine;std::vector<float> block(512);
    assert(process_command("F612.5",engine));assert(engine.period==18);
    assert(!process_command("F150",engine));assert(engine.period==18);
    assert(process_command("S 612.5 25 3 0 0",engine));assert(engine.front==3&&engine.volume==0.25f);
    assert(!process_command("S nan 50 3 0 0",engine));
    key_press(engine);engine.render(block.data(),block.size());assert(engine.hardware);
    assert(process_command("M1",engine));engine.render(block.data(),block.size());engine.render(block.data(),block.size());
    for(float x:block)assert(x==0);
    assert(process_command("M0",engine));engine.render(block.data(),block.size());assert(block[100]!=0);
    key_release(engine);engine.render(block.data(),block.size());
    assert(process_command("K local 1",engine));assert(process_command("K remote 1",engine));
    assert(process_command("K local 0",engine));assert(engine.remote&&!engine.local);
    assert(process_command("RESET",engine));assert(!engine.remote&&!engine.local);
    engine.render(block.data(),block.size());
    assert(process_command("P 80 50 23 30 30 6 0 0 0 .|.-..",engine));
    engine.render(block.data(),256);
    assert(process_command("K remote 1",engine));engine.render(block.data(),256);
    bool cancelled=false;morse::Event event;
    while(engine.poll(event))if(event.type==morse::EventType::Done&&event.id==80)cancelled=event.value==1;
    assert(cancelled);assert(process_command("RESET",engine));
    assert(!process_command("P 81 0 23 30 30 6 0 0 0 .",engine));
    assert(!process_command("P 81 50 23 30 30 6 0 0 0 garbage",engine));
    assert(!process_command("P 81 50 23 30 30 6 0 0 0 . extra",engine));
    assert(process_command("P 90 50 23 30 30 6 0 0 0 .",engine));
    assert(process_command("P 91 50 23 30 30 6 0 0 0 .",engine));
    assert(process_command("STOP 90",engine));engine.render(block.data(),256);
    bool wrongStop=false;while(engine.poll(event))if(event.type==morse::EventType::Done&&event.id==91)wrongStop=true;
    assert(!wrongStop);engine.stop();engine.render(block.data(),256);while(engine.poll(event)){}
    // Concurrent command producer, audio callback, and event consumer.
    morse::Engine stress;std::atomic<bool> complete{false};
    std::thread producer([&]{for(uint32_t i=1;i<=1000;i++){while(!stress.submit(morse::makePlan(i,s,".-|...",48000)))std::this_thread::yield();}complete=true;});
    std::thread consumer([&]{morse::Event e;while(!complete){while(stress.poll(e)){}std::this_thread::yield();}});
    for(int i=0;!complete||i<500;i++)stress.render(block.data(),block.size());
    producer.join();consumer.join();
    std::cout<<"PASS: native PCM/timings, clocks, parser, mute, shared keys, cancellation and concurrency\n";
}
