#define TEST_RUNNER
#include "morze_engine_v2.cpp"
#include <assert.h>
#include <iostream>

void test_frequency_command() {
    MorseState state = {0};
    state.frequency = 700.0;
    
    process_command("F1000", state);
    assert(state.frequency == 1000.0);
    
    process_command("F150", state); // Too low, should be ignored
    assert(state.frequency == 1000.0);
    
    process_command("F2500", state); // Too high
    assert(state.frequency == 1000.0);
    
    std::cout << "test_frequency_command passed" << std::endl;
}

void test_volume_command() {
    MorseState state = {0};
    state.maxVolume = 0.5f;
    state.targetVolume = 0.0f;
    
    process_command("V100", state);
    assert(state.maxVolume == 1.0f);
    
    state.targetVolume = 0.5f;
    process_command("V80", state);
    assert(state.maxVolume == 0.8f);
    assert(state.targetVolume == 0.8f); // Should update target if active
    
    std::cout << "test_volume_command passed" << std::endl;
}

int main() {
    test_frequency_command();
    test_volume_command();
    std::cout << "--- ALL ENGINE TESTS PASSED ---" << std::endl;
    return 0;
}
