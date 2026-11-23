import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 银行卡 / 信用卡扫描解析结果
class CardScanResult {
  final String title;
  final String cardholder;
  final String cardNumber;
  final String expiry;
  final String cvv;
  final String rawText;

  const CardScanResult({
    this.title = '',
    this.cardholder = '',
    this.cardNumber = '',
    this.expiry = '',
    this.cvv = '',
    this.rawText = '',
  });
}

/// 证件（身份证 / 护照 / 驾照）扫描解析结果
class IdCardScanResult {
  final String title;
  final String name;
  final String idNumber;
  final String expiry;
  final String issuer;
  final String address;
  final String rawText;

  const IdCardScanResult({
    this.title = '',
    this.name = '',
    this.idNumber = '',
    this.expiry = '',
    this.issuer = '',
    this.address = '',
    this.rawText = '',
  });
}

/// 基于设备原生视觉（iOS / macOS VisionKit）的文字识别与智能提取服务
class VisionOcr {
  static const _ch = MethodChannel('clipboard/vision_ocr');

  static bool get isPlatformSupported => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// 检查当前系统是否支持设备端 Vision OCR
  static Future<bool> isSupported() async {
    if (!isPlatformSupported) return false;
    try {
      final res = await _ch.invokeMethod<bool>('isSupported');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// 识别图片中的文字并返回整段文本与分行列表
  static Future<Map<String, dynamic>?> recognizeText(String imagePath) async {
    if (!isPlatformSupported) return null;
    try {
      final res = await _ch.invokeMapMethod<String, dynamic>('recognizeText', {'path': imagePath});
      return res;
    } catch (e) {
      debugPrint('VisionOcr.recognizeText failed: $e');
      return null;
    }
  }

  /// 智能解析银行卡 / 信用卡信息
  static CardScanResult parseCard(List<String> lines) {
    String title = '';
    String cardholder = '';
    String cardNumber = '';
    String expiry = '';
    String cvv = '';

    final bankKeywords = [
      '招商银行', '中国工商银行', '工商银行', '中国建设银行', '建设银行',
      '中国农业银行', '农业银行', '交通银行', '中信银行', '中国银行',
      '民生银行', '广发银行', '平安银行', '浦发银行', '兴业银行',
      '光大银行', '华夏银行', '邮政储蓄', '汇丰银行', '渣打银行',
      'VISA', 'Visa', 'Mastercard', 'MasterCard', '银联', 'UnionPay', 'JCB', 'American Express'
    ];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 1. 发卡行/卡片名称
      if (title.isEmpty) {
        for (final b in bankKeywords) {
          if (trimmed.contains(b)) {
            title = trimmed;
            break;
          }
        }
      }

      // 2. 卡号：带空格或连续的 15~19 位数字
      if (cardNumber.isEmpty) {
        final cardMatch = RegExp(r'\b(?:\d{4}[ -]?){3,4}\d{3,4}\b|\b\d{15,19}\b').firstMatch(trimmed);
        if (cardMatch != null) {
          final digits = cardMatch.group(0)!.replaceAll(RegExp(r'[ -]'), '');
          if (digits.length >= 15 && digits.length <= 19) {
            cardNumber = digits;
          }
        }
      }

      // 3. 有效期：MM/YY
      if (expiry.isEmpty) {
        final expMatch = RegExp(r'(?:VALID\s+THRU|EXPIRES|MONTH/YEAR|月/年|有效期)?\s*(0[1-9]|1[0-2])\s*[\/\-]\s*([2-3]\d)\b', caseSensitive: false)
            .firstMatch(trimmed);
        if (expMatch != null) {
          expiry = '${expMatch.group(1)}/${expMatch.group(2)}';
        }
      }

      // 4. CVV
      if (cvv.isEmpty) {
        final cvvMatch = RegExp(r'\b(?:CVV|CVC|CID|安全码)?\s*(\d{3,4})\b', caseSensitive: false).firstMatch(trimmed);
        if (cvvMatch != null && cvvMatch.group(1) != cardNumber) {
          final val = cvvMatch.group(1)!;
          if (val.length == 3 || val.length == 4) {
            if (trimmed.toLowerCase().contains('cvv') || trimmed.toLowerCase().contains('cvc')) {
              cvv = val;
            }
          }
        }
      }

      // 5. 持卡人姓名（大写拼音如 ZHANG SAN）
      if (cardholder.isEmpty) {
        final nameMatch = RegExp(r'^[A-Z]{2,15}\s+[A-Z]{2,15}(\s+[A-Z]{2,15})?$').firstMatch(trimmed);
        if (nameMatch != null) {
          final cand = nameMatch.group(0)!;
          if (!cand.contains('BANK') && !cand.contains('VALID') && !cand.contains('THRU') && !cand.contains('CARD') && !cand.contains('UNIONPAY')) {
            cardholder = cand;
          }
        }
      }
    }

    if (title.isEmpty) {
      title = cardNumber.isNotEmpty ? '银行卡' : '卡片';
    }

    return CardScanResult(
      title: title,
      cardholder: cardholder,
      cardNumber: cardNumber,
      expiry: expiry,
      cvv: cvv,
      rawText: lines.join('\n'),
    );
  }

  /// 智能解析证件信息（居民身份证、护照等）
  static IdCardScanResult parseIdCard(List<String> lines) {
    String title = '居民身份证';
    String name = '';
    String idNumber = '';
    String expiry = '';
    String issuer = '';
    String address = '';

    final idRegex = RegExp(r'\b([1-9]\d{5}(?:18|19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx])\b');
    final passportRegex = RegExp(r'\b([EGEg]\d{8}|[A-Za-z]\d{7,8})\b');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // 1. 身份证号
      if (idNumber.isEmpty) {
        final idMatch = idRegex.firstMatch(line);
        if (idMatch != null) {
          idNumber = idMatch.group(1)!;
          title = '居民身份证';
        }
      }

      // 2. 姓名
      if (name.isEmpty) {
        if (line.startsWith('姓名') || line.startsWith('名')) {
          final cand = line.replaceAll(RegExp(r'^[姓名\s:：]+'), '').trim();
          if (cand.isNotEmpty && cand.length <= 6) {
            name = cand;
          } else if (i + 1 < lines.length) {
            final next = lines[i + 1].trim();
            if (next.length >= 2 && next.length <= 6 && RegExp(r'^[\u4e00-\u9fa5]+$').hasMatch(next)) {
              name = next;
            }
          }
        }
      }

      // 3. 有效期
      if (expiry.isEmpty) {
        if (line.contains('长期')) {
          expiry = '长期';
        } else {
          final dateRange = RegExp(r'(\d{4}[.\-年]\d{1,2}[.\-月]\d{1,2})\s*[-至到—~]\s*(\d{4}[.\-年]\d{1,2}[.\-月]\d{1,2}|长期)').firstMatch(line);
          if (dateRange != null) {
            expiry = dateRange.group(0)!;
          }
        }
      }

      // 4. 签发机关
      if (issuer.isEmpty) {
        if (line.contains('签发机关') || line.contains('机关')) {
          final cand = line.replaceAll(RegExp(r'^[签发机关\s:：]+'), '').trim();
          if (cand.isNotEmpty) {
            issuer = cand;
          } else if (i + 1 < lines.length) {
            issuer = lines[i + 1].trim();
          }
        } else if (line.contains('公安局') || line.contains('分局')) {
          issuer = line;
        }
      }

      // 5. 住址
      if (address.isEmpty) {
        if (line.startsWith('住址') || line.startsWith('址')) {
          address = line.replaceAll(RegExp(r'^[住址\s:：]+'), '').trim();
        }
      }

      // 6. 护照判断
      if (idNumber.isEmpty && (line.contains('PASSPORT') || line.contains('护照'))) {
        title = '护照';
        final passMatch = passportRegex.firstMatch(line);
        if (passMatch != null) {
          idNumber = passMatch.group(1)!;
        }
      }
    }

    return IdCardScanResult(
      title: title,
      name: name,
      idNumber: idNumber,
      expiry: expiry,
      issuer: issuer,
      address: address,
      rawText: lines.join('\n'),
    );
  }
}
