//! Identify Windows touchpad wheel packets without guessing from wheel precision.
//! Only an application's own, explicitly attached windows are observed. The OS
//! callback records metadata; Godot still receives and routes the original input.

#[cfg(any(windows, test))]
mod queue {
    use std::collections::VecDeque;

    #[derive(Clone, Copy)]
    pub struct Packet {
        pub window: usize,
        pub axis: i32,
        pub delta: f64,
        pub touchpad: bool,
        pub time: u64,
    }

    #[derive(Default)]
    pub struct Queue(VecDeque<Packet>);

    impl Queue {
        pub fn push(&mut self, packet: Packet) {
            // Godot drops zero-distance wheel messages before emitting input.
            // They must not shift the metadata queue relative to real events.
            if !packet.delta.is_finite() || packet.delta == 0.0 {
                return;
            }
            if self.0.len() >= 256 {
                self.0.pop_front();
            }
            self.0.push_back(packet);
        }

        pub fn take(&mut self, window: usize, axis: i32, delta: f64, now: u64) -> bool {
            self.0.retain(|p| now.saturating_sub(p.time) <= 1000);
            // Every native packet, including real mice, occupies one slot.
            // A mismatched packet must never identify a different input device.
            let Some(index) = self.0.iter().position(|p| p.window == window) else {
                return false;
            };
            let Some(packet) = self.0.remove(index) else {
                return false;
            };
            packet.axis == axis && (packet.delta - delta).abs() < 0.001 && packet.touchpad
        }

        pub fn remove_window(&mut self, window: usize) {
            self.0.retain(|p| p.window != window);
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn device_identity_is_not_a_precision_heuristic() {
            let mut queue = Queue::default();
            for (touchpad, delta) in [(false, 0.25), (true, 1.0), (false, 1.0), (true, -0.5)] {
                queue.push(Packet {
                    window: 7,
                    axis: 1,
                    delta,
                    touchpad,
                    time: 100,
                });
                assert_eq!(queue.take(7, 1, delta, 101), touchpad);
            }
            assert!(!queue.take(7, 1, 1.0, 101));
        }

        #[test]
        fn stale_mismatched_and_other_window_packets_cannot_tag_a_mouse() {
            let mut queue = Queue::default();
            let packet = Packet {
                window: 7,
                axis: 1,
                delta: 1.0,
                touchpad: true,
                time: 100,
            };
            queue.push(packet);
            assert!(!queue.take(8, 1, 1.0, 101));
            assert!(!queue.take(7, 0, 1.0, 101));
            queue.push(packet);
            assert!(!queue.take(7, 1, 1.0, 1101));
            queue.push(packet);
            queue.remove_window(7);
            assert!(!queue.take(7, 1, 1.0, 101));
        }

        #[test]
        fn unconsumed_input_has_bounded_storage() {
            let mut queue = Queue::default();
            for time in 0..1000 {
                queue.push(Packet {
                    window: 7,
                    axis: 1,
                    delta: 1.0,
                    touchpad: true,
                    time,
                });
            }
            assert_eq!(queue.0.len(), 256);
        }

        #[test]
        fn zero_distance_packets_do_not_shift_device_metadata() {
            let mut queue = Queue::default();
            for delta in [0.0, f64::NAN, f64::INFINITY] {
                queue.push(Packet {
                    window: 7,
                    axis: 1,
                    delta,
                    touchpad: false,
                    time: 100,
                });
            }
            queue.push(Packet {
                window: 7,
                axis: 1,
                delta: 0.25,
                touchpad: true,
                time: 100,
            });
            assert!(queue.take(7, 1, 0.25, 101));
        }
    }
}

#[cfg(windows)]
mod os {
    use super::queue::{Packet, Queue};
    use std::cell::RefCell;
    use std::collections::HashMap;
    use std::ffi::{c_char, c_void};

    type Window = *mut c_void;
    type Subclass = unsafe extern "system" fn(Window, u32, usize, isize, usize, usize) -> isize;
    type RegisterThread = unsafe extern "system" fn(i32) -> i32;
    const SUBCLASS_ID: usize = 0x52534e41;
    const WM_MOUSEWHEEL: u32 = 0x020a;
    const WM_MOUSEHWHEEL: u32 = 0x020e;
    const WM_NCDESTROY: u32 = 0x0082;
    const TOUCHPAD: u32 = 0x10;

    #[repr(C)]
    struct MessageSource {
        device: u32,
        origin: u32,
    }

    #[link(name = "comctl32")]
    unsafe extern "system" {
        fn SetWindowSubclass(window: Window, callback: Subclass, id: usize, data: usize) -> i32;
        fn RemoveWindowSubclass(window: Window, callback: Subclass, id: usize) -> i32;
        fn DefSubclassProc(window: Window, message: u32, wparam: usize, lparam: isize) -> isize;
    }
    #[link(name = "user32")]
    unsafe extern "system" {
        fn GetCurrentInputMessageSource(source: *mut MessageSource) -> i32;
        fn GetWindowThreadProcessId(window: Window, process: *mut u32) -> u32;
    }
    #[link(name = "kernel32")]
    unsafe extern "system" {
        fn GetModuleHandleW(name: *const u16) -> *mut c_void;
        fn GetProcAddress(module: *mut c_void, name: *const c_char) -> *mut c_void;
        fn GetCurrentThreadId() -> u32;
        fn GetTickCount64() -> u64;
    }

    #[derive(Default)]
    struct State {
        windows: HashMap<usize, usize>,
        packets: Queue,
        registered: Option<RegisterThread>,
    }
    thread_local! {
        static STATE: RefCell<State> = RefCell::new(State::default());
    }

    fn now() -> u64 {
        // SAFETY: GetTickCount64 has no preconditions.
        unsafe { GetTickCount64() }
    }

    fn registration() -> Option<RegisterThread> {
        let name: Vec<u16> = "user32.dll\0".encode_utf16().collect();
        // SAFETY: the system library is already loaded; the buffer is terminated.
        let module = unsafe { GetModuleHandleW(name.as_ptr()) };
        if module.is_null() {
            return None;
        }
        // Optional opt-in on Windows versions that expose the named API. Never
        // guess an ordinal on older User32 builds. Drivers whose source cannot
        // be identified retain their existing mouse behavior.
        // SAFETY: the loaded module and NUL-terminated symbol name are valid.
        let address = unsafe { GetProcAddress(module, c"RegisterTouchpadCapableThread".as_ptr()) };
        if address.is_null() {
            return None;
        }
        // SAFETY: this is the documented RegisterTouchpadCapableThread(BOOL) signature.
        Some(unsafe { std::mem::transmute::<*mut c_void, RegisterThread>(address) })
    }

    pub fn attach(handle: usize) -> bool {
        let window = handle as Window;
        // SAFETY: querying a window handle is allowed; invalid handles return zero.
        if handle == 0 || unsafe { GetWindowThreadProcessId(window, std::ptr::null_mut()) != GetCurrentThreadId() } {
            return false;
        }
        let existing = STATE.with(|state| {
            let mut state = state.borrow_mut();
            if let Some(count) = state.windows.get_mut(&handle) {
                *count += 1;
                true
            } else {
                false
            }
        });
        if existing {
            return true;
        }
        // SAFETY: the caller owns this window on the current thread. The callback
        // remains in this library until the matching detach / WM_NCDESTROY.
        if unsafe { SetWindowSubclass(window, callback, SUBCLASS_ID, 0) } == 0 {
            return false;
        }
        let first = STATE.with(|state| state.borrow().windows.is_empty());
        let register = if first { registration() } else { None };
        let registered = register.filter(|register| {
            // SAFETY: registration changes only this thread, balanced on detach.
            unsafe { register(1) != 0 }
        });
        STATE.with(|state| {
            let mut state = state.borrow_mut();
            state.windows.insert(handle, 1);
            if first {
                state.registered = registered;
            }
        });
        true
    }

    pub fn detach(handle: usize) {
        detach_window(handle, false);
    }

    fn detach_window(handle: usize, destroyed: bool) {
        let removed = STATE.with(|state| {
            let mut state = state.borrow_mut();
            let Some(count) = state.windows.get_mut(&handle) else {
                return false;
            };
            if *count > 1 && !destroyed {
                *count -= 1;
                return false;
            }
            state.windows.remove(&handle);
            state.packets.remove_window(handle);
            true
        });
        if !removed {
            return;
        }
        // SAFETY: remove only the subclass registered above on this same thread.
        unsafe { RemoveWindowSubclass(handle as Window, callback, SUBCLASS_ID) };
        let unregister = STATE.with(|state| {
            let mut state = state.borrow_mut();
            if state.windows.is_empty() { state.registered.take() } else { None }
        });
        if let Some(unregister) = unregister {
            // SAFETY: balance our one successful registration, preserving others.
            unsafe { unregister(0) };
        }
    }

    unsafe extern "system" fn callback(window: Window, message: u32, wparam: usize, lparam: isize, _id: usize, _data: usize) -> isize {
        if message == WM_MOUSEWHEEL || message == WM_MOUSEHWHEEL {
            let mut source = MessageSource { device: 0, origin: 0 };
            // SAFETY: this is the current window message; source points to a live struct.
            let touchpad = unsafe { GetCurrentInputMessageSource(&mut source) != 0 } && source.device == TOUCHPAD;
            let delta = f64::from(((wparam >> 16) as u16) as i16) / 120.0;
            STATE.with(|state| {
                state.borrow_mut().packets.push(Packet {
                    window: window as usize,
                    axis: i32::from(message == WM_MOUSEWHEEL),
                    delta,
                    touchpad,
                    time: now(),
                })
            });
        } else if message == WM_NCDESTROY {
            detach_window(window as usize, true);
        }
        // SAFETY: forward every original message and result. No Godot APIs are
        // called here, and no RefCell borrow is held across this reentrant call.
        unsafe { DefSubclassProc(window, message, wparam, lparam) }
    }

    pub fn take(handle: usize, axis: i32, delta: f64) -> bool {
        STATE.with(|state| state.borrow_mut().packets.take(handle, axis, delta, now()))
    }
}

#[cfg(not(windows))]
mod os {
    pub fn attach(_handle: usize) -> bool {
        false
    }
    pub fn detach(_handle: usize) {}
    pub fn take(_handle: usize, _axis: i32, _delta: f64) -> bool {
        false
    }
}

pub use os::{attach, detach, take};
