"""Original recorded applicability rules; no network or model calls."""
SCOPE_GATE = {
 'core':'在线建立或维持关系时，按该建议明确提及的线索或请求适用。',
 'dating_safety':'涉及交友平台设置或安排线下会面；仅采用与当前活动匹配的步骤。',
 'investment':'仅在出现投资、交易平台、加密货币或钱包操作时适用。',
 'sextortion':'仅在私密影像、性勒索、影像传播风险或相关威胁出现时适用。',
 'recovery':'仅在已付款、已泄露信息、账号受侵或发现受骗后，按实际损害适用。',
 'support':'建议对象是正在帮助他人的亲友或支持人员，不直接冒充给潜在受骗者的建议。'
}

def applicability(key, members):
    scopes = sorted({r['scope'] for r in members})
    result = [SCOPE_GATE[x] for x in scopes]
    if key.startswith('military_'):
        result.append('仅涉及对方自称美国军人的情形；不以职业或国籍本身判定诈骗。')
    if key.startswith('hash_') or key in {'adult_hash_prevention','save_hash_case_pin'}:
        result.append('工具操作以 StopNCII 当时的资格和平台覆盖为限；相关影像须满足成人服务条件。')
    if key == 'image_age_service':
        result.append('成年人求助时如影像摄于未满 18 岁，转介未成年人影像服务；不要求重新获取影像。')
    if key in {'keep_payee_check','payee_mismatch_stop','card_channel_controls','temporary_card_freeze','personal_payment_limits'}:
        result.append('仅当用户的银行或支付渠道提供该功能时；姓名匹配或额度控制不保证交易安全。')
    if any(r['stage']=='recovery' for r in members):
        result.append('涉及追回款项时只表示可以请求处理，不承诺退款或追回成功。')
    if key in {'elder_reporting_assistance','official_report_address','fake_ic3_social','avoid_report_search_ads','mail_fraud_report'}:
        result.append('所述机构渠道属于美国；其他地区应使用相应本地渠道。')
    if key in {'scam_call_filter','anti_scam_helpline','no_identity_account_lending'}:
        result.append('所述 ScamShield 或 Singpass 服务属于新加坡。')
    result.append('国家、机构与工具名称须结合来源地区使用；此栏是研究用途适用性标注。')
    return result

