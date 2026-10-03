"""Original recorded applicability rules; no network or model calls."""
SCOPE_GATE = {
 'core':'Applicable when establishing or maintaining an online relationship, according to the cues or requests explicitly mentioned in the advice.',
 'dating_safety':'Applicable to dating-platform settings or arranging an in-person meeting; use only steps matching the current activity.',
 'investment':'Applicable only when investment, trading-platform, cryptocurrency, or wallet activity is present.',
 'sextortion':'Applicable only when intimate images, sextortion, image-distribution risks, or related threats are present.',
 'recovery':'Applicable after payment, information disclosure, account compromise, or discovery of fraud, according to the actual harm.',
 'support':'The advice addresses friends, relatives, or support workers helping another person; it is not presented directly as advice to a potential victim.'
}

def applicability(key, members):
    scopes = sorted({r['scope'] for r in members})
    result = [SCOPE_GATE[x] for x in scopes]
    if key.startswith('military_'):
        result.append('Applicable only when the contact claims to be a member of the US military; occupation or nationality alone is not evidence of fraud.')
    if key.startswith('hash_') or key in {'adult_hash_prevention','save_hash_case_pin'}:
        result.append('Use of StopNCII is subject to its eligibility requirements and platform coverage at the time; the images must meet adult-service conditions.')
    if key == 'image_age_service':
        result.append('If an adult seeks help for images taken before age 18, refer to the appropriate service for images of minors; do not require reacquiring the images.')
    if key in {'keep_payee_check','payee_mismatch_stop','card_channel_controls','temporary_card_freeze','personal_payment_limits'}:
        result.append('Applicable only if the user\'s bank or payment channel provides this feature; name matching and payment limits do not guarantee transaction safety.')
    if any(r['stage']=='recovery' for r in members):
        result.append('Advice about recovering funds means that assistance may be requested, not that a refund or recovery is guaranteed.')
    if key in {'elder_reporting_assistance','official_report_address','fake_ic3_social','avoid_report_search_ads','mail_fraud_report'}:
        result.append('The agency channels described are US-specific; use the corresponding local channels in other jurisdictions.')
    if key in {'scam_call_filter','anti_scam_helpline','no_identity_account_lending'}:
        result.append('The ScamShield or Singpass services mentioned are Singapore-specific.')
    result.append('Country, agency, and tool names must be interpreted in the source jurisdiction; this field is a research applicability annotation.')
    return result

