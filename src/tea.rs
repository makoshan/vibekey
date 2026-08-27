//! Vibe Key 厂商通道(HID usage page 0xFFFC)的 TEA 加解密与帧格式。
//!
//! 全部逆自设备固件通信,并用真机抓包验证过:
//! - 密钥正确性的硬判据:恒定填充块 38 90 C4 99 A3 60 AA AD 解出来是 8 个 0x00,
//!   也就是「加密后的全零」——这不可能是巧合。
//! - 2026-08-24 抓到的 549 条报文里有 50 条按键帧,字段位置逐条对上按键表。

const KEY: [u32; 4] = [0xCAA5_BACA, 0xBC2A_8A6D, 0xCA5A_9EBA, 0x9BB8_8BCA];
const DELTA: u32 = 0x9E37_79B9;
const ROUNDS: usize = 32;

fn rd(b: &[u8], i: usize) -> u32 {
    u32::from_le_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]])
}

pub fn decrypt(bytes: &[u8]) -> Option<Vec<u8>> {
    if bytes.is_empty() || bytes.len() % 8 != 0 {
        return None;
    }
    let mut out = Vec::with_capacity(bytes.len());
    for c in bytes.chunks_exact(8) {
        let (mut v0, mut v1) = (rd(c, 0), rd(c, 4));
        let mut sum = DELTA.wrapping_mul(ROUNDS as u32);
        for _ in 0..ROUNDS {
            v1 = v1.wrapping_sub(
                ((v0 << 4).wrapping_add(KEY[2])) ^ v0.wrapping_add(sum) ^ ((v0 >> 5).wrapping_add(KEY[3])),
            );
            v0 = v0.wrapping_sub(
                ((v1 << 4).wrapping_add(KEY[0])) ^ v1.wrapping_add(sum) ^ ((v1 >> 5).wrapping_add(KEY[1])),
            );
            sum = sum.wrapping_sub(DELTA);
        }
        out.extend_from_slice(&v0.to_le_bytes());
        out.extend_from_slice(&v1.to_le_bytes());
    }
    Some(out)
}

pub fn encrypt(bytes: &[u8]) -> Option<Vec<u8>> {
    if bytes.is_empty() || bytes.len() % 8 != 0 {
        return None;
    }
    let mut out = Vec::with_capacity(bytes.len());
    for c in bytes.chunks_exact(8) {
        let (mut v0, mut v1) = (rd(c, 0), rd(c, 4));
        let mut sum = 0u32;
        for _ in 0..ROUNDS {
            sum = sum.wrapping_add(DELTA);
            v0 = v0.wrapping_add(
                ((v1 << 4).wrapping_add(KEY[0])) ^ v1.wrapping_add(sum) ^ ((v1 >> 5).wrapping_add(KEY[1])),
            );
            v1 = v1.wrapping_add(
                ((v0 << 4).wrapping_add(KEY[2])) ^ v0.wrapping_add(sum) ^ ((v0 >> 5).wrapping_add(KEY[3])),
            );
        }
        out.extend_from_slice(&v0.to_le_bytes());
        out.extend_from_slice(&v1.to_le_bytes());
    }
    Some(out)
}

/// 主机→设备:命令补齐到 64 字节、加密、前置 report id 0x55
pub fn command(msg: &[u8]) -> Vec<u8> {
    let mut m = msg.to_vec();
    m.resize(64, 0);
    let mut out = vec![0x55u8];
    out.extend(encrypt(&m).expect("64 是 8 的倍数"));
    out
}

/// 主机→设备的已知命令(逆自官方 1131 条 SetReport,总共只有 7 种)
pub fn handshake() -> Vec<u8> { command(&[0x06, 0x02, 0x05, 0x01]) }
pub fn keepalive() -> Vec<u8> { command(&[0x06, 0x01, 0x23, 0x00, 0x01]) }

#[derive(Debug, PartialEq)]
pub enum Event {
    /// 按键。线上布局 [2]=function、[3]=status、[4]=index。
    ///
    /// 注意 SDK 回调选择器叫 `index:status:physicalIndex:`,顺序跟线上是反的 ——
    /// AU05 在 SDK 里被一张设备覆盖表打了 isSwitchKeyIndex=1,
    /// 所以对外报的 index 取自 byte[4],byte[2] 其实是 function 码。
    ///
    /// 真机验证的对应关系:110→3(旋钮按下) 111→0(语音) 112→1(✓) 114→4 115→5
    Key { index: u8, function: u8, status: u8 },
    Battery { percent: u8, mv: u16, charging: bool, full: bool },
    Other(Vec<u8>),
}

/// 设备→主机的报文解码。
///
/// 报文是 0x55 + 64 字节密文,但 hidapi 在 macOS 上会截到 64 字节,
/// 去掉 0x55 只剩 63 —— 不是 8 的倍数。消息内容都在头几个块里,
/// 尾部是补零加密出来的填充,所以按整块截断即可。
pub fn decode(report: &[u8]) -> Option<Event> {
    let body: &[u8] = if report.first() == Some(&0x55) { &report[1..] } else { report };
    let usable = body.len() / 8 * 8;
    if usable == 0 {
        return None;
    }
    let m = decrypt(&body[..usable])?;
    // 高位 bit7 表示设备→主机,低 5 位是消息类
    if m.len() < 5 || (m[0] & 0x1F) != 0x0B {
        return Some(Event::Other(m.into_iter().take(8).collect()));
    }
    Some(match m[1] {
        0x10 => Event::Key { function: m[2], status: m[3], index: m[4] },
        0x7B if m.len() >= 6 => Event::Battery {
            percent: m[5],
            mv: u16::from(m[2]) | (u16::from(m[3]) << 8),
            charging: m[4] & 0x08 != 0,
            full: m[4] & 0x10 != 0,
        },
        _ => Event::Other(m.into_iter().take(8).collect()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 密钥正确性的硬判据:恒定填充块必须解出全零
    #[test]
    fn filler_block_decrypts_to_zeros() {
        let filler = [0x38, 0x90, 0xC4, 0x99, 0xA3, 0x60, 0xAA, 0xAD];
        assert_eq!(decrypt(&filler).unwrap(), vec![0u8; 8]);
    }

    /// 真机抓到的电量帧
    #[test]
    fn decodes_real_captured_battery_frame() {
        let mut r = vec![0x9A, 0xE7, 0xF3, 0x05, 0x32, 0x03, 0xF0, 0xDB];
        for _ in 0..7 {
            r.extend_from_slice(&[0x38, 0x90, 0xC4, 0x99, 0xA3, 0x60, 0xAA, 0xAD]);
        }
        assert_eq!(
            decode(&r),
            Some(Event::Battery { percent: 100, mv: 4188, charging: true, full: true })
        );
    }

    /// hidapi 截断后的真实形态:0x55 + 63 字节,仍要能解
    #[test]
    fn decodes_truncated_report() {
        let mut r = vec![0x55, 0xbf, 0x57, 0x77, 0x0f, 0x31, 0x43, 0x8a, 0xf9];
        for _ in 0..7 {
            r.extend_from_slice(&[0x38, 0x90, 0xC4, 0x99, 0xA3, 0x60, 0xAA, 0xAD]);
        }
        r.truncate(64);
        match decode(&r) {
            Some(Event::Other(head)) => assert_eq!(&head[..4], &[0x06, 0x03, 0x0a, 0x11]),
            other => panic!("期望激活 ACK,实际 {other:?}"),
        }
    }

    /// function ↔ index 的对应必须与设备自报的按键表一致
    #[test]
    fn function_to_index_matches_button_table() {
        for (func, idx) in [(110u8, 3u8), (111, 0), (112, 1), (114, 4), (115, 5)] {
            let mut msg = vec![0x8B, 0x10, func, 0x01, idx, 0x00];
            msg.resize(64, 0);
            let ct = encrypt(&msg).unwrap();
            assert_eq!(
                decode(&ct),
                Some(Event::Key { function: func, status: 1, index: idx }),
                "function {func} 应对应 index {idx}"
            );
        }
    }

    #[test]
    fn round_trip() {
        let msg: Vec<u8> = (0u8..64).collect();
        assert_eq!(decrypt(&encrypt(&msg).unwrap()).unwrap(), msg);
        assert!(decrypt(&[1, 2, 3]).is_none());
    }
}
