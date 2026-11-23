// Simulator-only probe: talk to testmanagerd's remote-automation socket over DTX.
use idevice::dvt::message::AuxValue;
use idevice::dvt::remote_server::RemoteServerClient;
use std::env;
#[tokio::main]
async fn main() {
    let a: Vec<String> = env::args().collect();
    let (sock, bundle, path) = (a[1].clone(), a[2].clone(), a.get(3).cloned().unwrap_or_default());
    let stream = tokio::net::UnixStream::connect(&sock).await.expect("connect");
    let mut client = RemoteServerClient::new(stream);
    let mut ch = client.make_channel("dtxproxy:XCTDRemoteAutomationClient:XCTDRemoteAutomationServer").await.expect("channel");
    let send = |v: plist::Value| AuxValue::archived_value(v);
    ch.call_method(Some(plist::Value::String("_XCTD_beginSessionWithClientProtocolVersion:".into())), Some(vec![send(plist::Value::Integer(1u64.into()))]), true).await.expect("begin");
     let m = ch.read_message().await; if let Ok(ref mm) = m { if let Some(r) = &mm.raw_data { std::fs::write("/tmp/bgax/tmd_begin.bin", r).ok(); } } println!("begin reply: {:?}", m.map(|m| format!("{:?}", m.data)).unwrap_or_else(|e| format!("err {e:?}")).chars().take(4000).collect::<String>());
    let args = plist::Value::Array(a.iter().skip(4).map(|x| plist::Value::String(x.clone())).collect()); let envd = plist::Value::Dictionary(plist::Dictionary::new());
    ch.call_method(Some(plist::Value::String("_XCTD_launchRemoteRunnerWithBundleID:path:arguments:environment:".into())), Some(vec![send(plist::Value::String(bundle)), send(plist::Value::String(path)), send(args), send(envd)]), true).await.expect("launch");
     let m = ch.read_message().await; if let Ok(ref mm) = m { if let Some(r) = &mm.raw_data { std::fs::write("/tmp/bgax/tmd_launch.bin", r).ok(); } } println!("launch reply: {:?}", m.map(|m| format!("{:?} aux {:?}", m.data, m.aux)).unwrap_or_else(|e| format!("err {e:?}")).chars().take(4000).collect::<String>());
}
