// Copyright: Kartei contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

//! C interface to Anki's backend. Every call is a protobuf message in and a
//! protobuf message out, addressed by (service, method) index, exactly as
//! Anki's own Python bridge does it.

pub mod exam;

use std::slice;

use prost::Message;

use anki::backend::init_backend;
use anki::backend::Backend;

/// Bytes owned by Rust. Free with `kartei_free`. `ok` is false when the bytes
/// are an error (a UTF-8 message from `kartei_open`, an encoded
/// `anki.backend.BackendError` from `kartei_command`).
#[repr(C)]
pub struct KarteiBytes {
    pub ptr: *mut u8,
    pub len: usize,
    pub ok: bool,
}

fn out(bytes: Vec<u8>, ok: bool) -> KarteiBytes {
    let boxed = bytes.into_boxed_slice();
    let len = boxed.len();
    KarteiBytes { ptr: Box::into_raw(boxed) as *mut u8, len, ok }
}

unsafe fn input<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if ptr.is_null() || len == 0 { &[] } else { slice::from_raw_parts(ptr, len) }
}

/// Create a backend from an encoded `anki.backend.BackendInit`. On failure
/// returns null and, if `err` is not null, writes the message there.
///
/// # Safety
/// `init` must point to `len` readable bytes; `err` must be null or writable.
#[no_mangle]
pub unsafe extern "C" fn kartei_open(init: *const u8, len: usize, err: *mut KarteiBytes) -> *mut Backend {
    match init_backend(input(init, len)) {
        Ok(backend) => Box::into_raw(Box::new(backend)),
        Err(msg) => {
            if !err.is_null() {
                *err = out(msg.into_bytes(), false);
            }
            std::ptr::null_mut()
        }
    }
}

/// Run one backend method. Blocks; call it off the main thread.
///
/// # Safety
/// `backend` must come from `kartei_open` and not be closed; `data` must point
/// to `len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn kartei_command(backend: *const Backend, service: u32, method: u32, data: *const u8, len: usize) -> KarteiBytes {
    match (*backend).run_service_method(service, method, input(data, len)) {
        Ok(bytes) => out(bytes, true),
        Err(bytes) => out(bytes, false),
    }
}

/// # Safety
/// `bytes` must come from this library and be freed once.
#[no_mangle]
pub unsafe extern "C" fn kartei_free(bytes: KarteiBytes) {
    if !bytes.ptr.is_null() {
        drop(Box::from_raw(slice::from_raw_parts_mut(bytes.ptr, bytes.len)));
    }
}

/// # Safety
/// `backend` must come from `kartei_open` and not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn kartei_close(backend: *mut Backend) {
    if !backend.is_null() {
        drop(Box::from_raw(backend));
    }
}

/// Cap the answer states (encoded `anki.scheduler.SchedulingStates`) for an exam `days_left` days away.
/// Returns the re-encoded states; on bad input returns the input unchanged with ok = false.
///
/// # Safety
/// `data` must point to `len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn kartei_cap_states(data: *const u8, len: usize, days_left: i32) -> KarteiBytes {
    let bytes = input(data, len);
    match anki_proto::scheduler::SchedulingStates::decode(bytes) {
        Ok(states) => out(exam::cap_states(states, days_left).encode_to_vec(), true),
        Err(_) => out(bytes.to_vec(), false),
    }
}

/// Version of the Anki backend this library was built from.
#[no_mangle]
pub extern "C" fn kartei_anki_version() -> KarteiBytes {
    out(anki::version::version().as_bytes().to_vec(), true)
}

/// JNI entry points for `app.kartei.core.Native`. `command` returns one status
/// byte (1 = ok, 0 = encoded BackendError) followed by the payload.
#[cfg(target_os = "android")]
mod android {
    use jni::objects::{JByteArray, JClass};
    use jni::sys::{jint, jlong};
    use jni::JNIEnv;

    use super::*;

    #[no_mangle]
    pub extern "system" fn Java_app_kartei_core_Native_open<'l>(env: JNIEnv<'l>, _class: JClass<'l>, init: JByteArray<'l>) -> jlong {
        let bytes = env.convert_byte_array(&init).unwrap_or_default();
        match init_backend(&bytes) {
            Ok(backend) => Box::into_raw(Box::new(backend)) as jlong,
            Err(_) => 0,
        }
    }

    #[no_mangle]
    pub extern "system" fn Java_app_kartei_core_Native_command<'l>(env: JNIEnv<'l>, _class: JClass<'l>, handle: jlong, service: jint, method: jint, input: JByteArray<'l>) -> JByteArray<'l> {
        let bytes = env.convert_byte_array(&input).unwrap_or_default();
        let backend = unsafe { &*(handle as *const Backend) };
        let (status, payload) = match backend.run_service_method(service as u32, method as u32, &bytes) {
            Ok(out) => (1u8, out),
            Err(err) => (0u8, err),
        };
        let mut framed = Vec::with_capacity(payload.len() + 1);
        framed.push(status);
        framed.extend_from_slice(&payload);
        env.byte_array_from_slice(&framed).expect("allocate result array")
    }

    #[no_mangle]
    pub extern "system" fn Java_app_kartei_core_Native_capStates<'l>(env: JNIEnv<'l>, _class: JClass<'l>, states: JByteArray<'l>, days_left: jint) -> JByteArray<'l> {
        let bytes = env.convert_byte_array(&states).unwrap_or_default();
        let capped = match anki_proto::scheduler::SchedulingStates::decode(bytes.as_slice()) {
            Ok(s) => crate::exam::cap_states(s, days_left).encode_to_vec(),
            Err(_) => bytes,
        };
        env.byte_array_from_slice(&capped).expect("allocate result array")
    }

    #[no_mangle]
    pub extern "system" fn Java_app_kartei_core_Native_version<'l>(env: JNIEnv<'l>, _class: JClass<'l>) -> jni::objects::JString<'l> {
        env.new_string(anki::version::version()).expect("allocate version string")
    }

    #[no_mangle]
    pub extern "system" fn Java_app_kartei_core_Native_close<'l>(_env: JNIEnv<'l>, _class: JClass<'l>, handle: jlong) {
        if handle != 0 {
            unsafe { drop(Box::from_raw(handle as *mut Backend)) };
        }
    }
}
