use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering};

/// Includes dependencies and serialization. Failed reservation returns null;
/// Rust then terminates this helper without a completion receipt. The parent
/// must require both receipt and successful exit, never accept partial records.
pub struct BoundedHeap;
pub const HEAP_LIMIT: usize = 64 * 1024 * 1024;
static LIVE: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);

fn reserve(bytes: usize) -> bool {
    let result = LIVE.fetch_update(Ordering::AcqRel, Ordering::Acquire, |live| {
        live.checked_add(bytes).filter(|next| *next <= HEAP_LIMIT)
    });
    if let Ok(previous) = result {
        PEAK.fetch_max(previous + bytes, Ordering::Relaxed);
        true
    } else {
        false
    }
}

pub fn peak() -> usize {
    PEAK.load(Ordering::Relaxed)
}

unsafe impl GlobalAlloc for BoundedHeap {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if !reserve(layout.size()) {
            return std::ptr::null_mut();
        }
        let ptr = unsafe { System.alloc(layout) };
        if ptr.is_null() {
            LIVE.fetch_sub(layout.size(), Ordering::AcqRel);
        }
        ptr
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) };
        LIVE.fetch_sub(layout.size(), Ordering::AcqRel);
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        let increase = size.saturating_sub(layout.size());
        if !reserve(increase) {
            return std::ptr::null_mut();
        }
        let new_ptr = unsafe { System.realloc(ptr, layout, size) };
        if new_ptr.is_null() {
            LIVE.fetch_sub(increase, Ordering::AcqRel);
        } else if size < layout.size() {
            LIVE.fetch_sub(layout.size() - size, Ordering::AcqRel);
        }
        new_ptr
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // This allocator is installed only in the helper binary, not the test host.
    // Exercise reservation refusal and realloc preservation directly.
    #[test]
    fn alloc_realloc_and_refusal_preserve_live_accounting() {
        unsafe {
            let heap = BoundedHeap;
            let small = Layout::from_size_align(32, 8).unwrap();
            let ptr = heap.alloc(small);
            assert!(!ptr.is_null());
            assert_eq!(LIVE.load(Ordering::Acquire), 32);
            let grown = heap.realloc(ptr, small, 64);
            assert!(!grown.is_null());
            assert_eq!(LIVE.load(Ordering::Acquire), 64);
            let large = Layout::from_size_align(64, 8).unwrap();
            assert!(heap.realloc(grown, large, HEAP_LIMIT + 1).is_null());
            assert_eq!(LIVE.load(Ordering::Acquire), 64);
            let shrunk = heap.realloc(grown, large, 16);
            assert!(!shrunk.is_null());
            assert_eq!(LIVE.load(Ordering::Acquire), 16);
            heap.dealloc(shrunk, Layout::from_size_align(16, 8).unwrap());
            assert_eq!(LIVE.load(Ordering::Acquire), 0);
            assert!(
                heap.alloc(Layout::from_size_align(HEAP_LIMIT + 1, 8).unwrap())
                    .is_null()
            );
            assert_eq!(LIVE.load(Ordering::Acquire), 0);
        }
    }
}
