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

void test_mute_command_mid_press() {
    MorseState state = {0};
    state.maxVolume = 0.5f;

    key_press(state);
    assert(state.targetVolume == 0.5f);

    process_command("M1", state); // Mute while the key is held: tone stops now
    assert(state.targetVolume == 0.0f);

    process_command("M0", state); // Unmute while still held: tone resumes
    assert(state.targetVolume == 0.5f);

    key_release(state);
    process_command("M0", state); // Unmute with key up: stays silent
    assert(state.targetVolume == 0.0f);

    process_command("M1", state);
    key_press(state); // Press while muted: silent
    assert(state.targetVolume == 0.0f);

    std::cout << "test_mute_command_mid_press passed" << std::endl;
}

int main() {
    test_frequency_command();
    test_volume_command();
    test_mute_command_mid_press();
    std::cout << "--- ALL ENGINE TESTS PASSED ---" << std::endl;
    return 0;
}
