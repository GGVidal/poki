//! rsd-probe <udid> [service ...]
//! 1. Opens a CoreDevice tunnel in userspace over usbmuxd (no utun, no root).
//! 2. Prints every RSD service with entitlement, port, RemoteXPC flag, version, features.
//! 3. For each named service: connects; for RemoteXPC services sends only the empty
//!    RemoteXPC handshake and prints the first message; for others sends nothing and
//!    prints the first bytes the service sends (or that it closed). Then disconnects.
use idevice::{core_device_proxy::CoreDeviceProxy, rsd::RsdHandshake, usbmuxd::{UsbmuxdAddr, UsbmuxdConnection}, xpc::RemoteXpcClient, IdeviceService};
use std::time::Duration;
use tokio::io::AsyncReadExt;

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    let udid = args.get(1).expect("usage: rsd-probe <udid> [service ...]").clone();
    let mut mux = UsbmuxdConnection::default().await.expect("usbmuxd");
    let dev = mux.get_devices().await.expect("devices").into_iter().find(|d| d.udid == udid).expect("phone not in usbmuxd list");
    let provider = dev.to_provider(UsbmuxdAddr::default(), "rsd-probe");
    let proxy = CoreDeviceProxy::connect(&provider).await.expect("CoreDeviceProxy");
    let rsd_port = proxy.tunnel_info().server_rsd_port;
    let mut adapter = proxy.create_software_tunnel().expect("software tunnel").to_async_handle();
    let rsd = RsdHandshake::new(adapter.connect(rsd_port).await.expect("rsd connect")).await.expect("rsd handshake");
    println!("RSD protocol_version={} services={}", rsd.protocol_version, rsd.services.len());
    let mut names: Vec<_> = rsd.services.keys().cloned().collect();
    names.sort();
    for n in &names {
        let s = &rsd.services[n];
        println!("SERVICE {n} entitlement={} port={} remotexpc={} version={:?} features={:?}", s.entitlement, s.port, s.uses_remote_xpc, s.service_version, s.features);
    }
    for want in &args[2..] {
        let Some(s) = rsd.services.get(want) else { println!("PROBE {want}: not advertised"); continue };
        let sock = match tokio::time::timeout(Duration::from_secs(10), adapter.connect(s.port)).await {
            Ok(Ok(sock)) => sock,
            Ok(Err(e)) => { println!("PROBE {want}: connect error {e:?}"); continue }
            Err(_) => { println!("PROBE {want}: connect timed out"); continue }
        };
        if s.uses_remote_xpc {
            let r = tokio::time::timeout(Duration::from_secs(8), async {
                let mut c = RemoteXpcClient::new(sock).await?;
                c.do_handshake().await?;
                c.recv_any().await
            }).await;
            match r {
                Ok(Ok(v)) => println!("PROBE {want}: handshake ok, first message: {v:?}"),
                Ok(Err(e)) => println!("PROBE {want}: handshake error {e:?}"),
                Err(_) => println!("PROBE {want}: handshake done, no message within 8 s"),
            }
        } else {
            let mut sock = sock;
            let mut buf = vec![0u8; 512];
            match tokio::time::timeout(Duration::from_secs(5), sock.read(&mut buf)).await {
                Ok(Ok(0)) => println!("PROBE {want}: service closed the connection without data"),
                Ok(Ok(n)) => println!("PROBE {want}: {n} bytes first: {:02x?}", &buf[..n.min(48)]),
                Ok(Err(e)) => println!("PROBE {want}: read error {e:?}"),
                Err(_) => println!("PROBE {want}: connection open, nothing sent by the service within 5 s"),
            }
        }
    }
}
