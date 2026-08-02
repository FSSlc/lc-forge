#include <cpptrace/cpptrace.hpp>
#include <cstdlib>
#include <cstring>
#include <iostream>

void trace() {
    cpptrace::generate_trace().print();
    #ifdef TEST_LIBUNWIND
    if(!cpptrace::can_signal_safe_unwind()) {
        std::cout<<"Test failed: !cpptrace::can_signal_safe_unwind()"<<std::endl;
        abort();
    }
    cpptrace::frame_ptr buffer[10];
    std::size_t count = cpptrace::safe_generate_raw_trace(buffer, 10);
    if(count == 0) {
        std::cout<<"Test failed: cpptrace::safe_generate_raw_trace found no frames"<<std::endl;
        abort();
    }
    // TODO: Re-enable once conda-forge has a newer libc
    // cpptrace::safe_object_frame frame;
    // cpptrace::get_safe_object_frame(buffer[0], &frame);
    // if(frame.address_relative_to_object_start == 0 && strlen(frame.object_path) == 0) {
    //     std::cout<<"Test failed: cpptrace::get_safe_object_frame didn't resolve (_dl_find_object likely isn't available)"<<std::endl;
    //     abort();
    // }
    #endif
}

void foo(int) {
    trace();
}

int main() {
    foo(0);
}
