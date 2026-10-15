import 'package:flutter/material.dart';

import '../presentation/guided_journey_screen.dart';

abstract final class JourneyCatalog {
  static const agreementApprovalOwner = [
    JourneyStep(
      title: 'Rahul sent your agreement',
      subtitle: 'Phoenix Towers 402 · Made for Rajesh Kumar',
      icon: Icons.description_outlined,
      items: [
        'Rent ₹22,000 every month',
        'Deposit ₹44,000 held by TrustKeyper',
        'Starts 1 October 2026 for 11 months',
        'Your brokerage share ₹11,000',
      ],
      action: 'Check the agreement',
    ),
    JourneyStep(
      title: 'Check what matters to you',
      subtitle: 'Your details are highlighted in the agreement.',
      icon: Icons.fact_check_outlined,
      items: [
        'Rent arrives on the 7th after charges',
        '2-month deposit stays protected',
        '6-month lock-in · 1-month notice',
        'TrustKeyper fee follows your owner contract',
      ],
      action: 'Read full agreement',
    ),
    JourneyStep(
      title: 'Do you agree?',
      subtitle: 'Nothing is final until you confirm both points.',
      icon: Icons.verified_user_outlined,
      items: [
        'I have read the full agreement',
        'The details and amounts are correct',
      ],
      action: 'Yes, I agree',
    ),
    JourneyStep(
      title: 'You said yes',
      subtitle: 'Rahul and the other people can see your reply.',
      icon: Icons.check_circle_outline_rounded,
      items: ['We will tell you when the stamp-paper copy is ready to sign.'],
      action: 'Done',
      tone: JourneyTone.success,
    ),
  ];

  static const agreementApprovalTenant = [
    JourneyStep(
      title: 'Check your agreement',
      subtitle: 'Phoenix Towers 402 · Your share is shown separately.',
      icon: Icons.description_outlined,
      items: [
        'Your rent share ₹11,000 of ₹22,000',
        'Your deposit share ₹22,000',
        'Rent is due by the 5th',
        'No late fee · the team follows up by hand',
      ],
      action: 'Read full agreement',
    ),
    JourneyStep(
      title: 'Do you agree?',
      subtitle: 'Confirm only after checking your name, share and dates.',
      icon: Icons.verified_user_outlined,
      items: [
        'I have read the agreement',
        'My rent and deposit share are correct',
      ],
      action: 'Yes, I agree',
    ),
    JourneyStep(
      title: 'You said yes',
      subtitle: 'We will tell you when it is ready to sign.',
      icon: Icons.check_circle_outline_rounded,
      tone: JourneyTone.success,
      action: 'Done',
    ),
  ];

  static const aadhaarSigning = [
    JourneyStep(
      title: 'Your agreement is ready to sign',
      subtitle: 'Read the stamp-paper copy before signing.',
      icon: Icons.draw_outlined,
      items: [
        'Telangana e-stamp paper · ₹100',
        '4 pages · checked by TrustKeyper',
        'All approved details are unchanged',
      ],
      action: 'Sign with Aadhaar',
    ),
    JourneyStep(
      title: 'Confirm your Aadhaar',
      subtitle: 'The OTP goes to the phone linked to Aadhaar.',
      icon: Icons.fingerprint_rounded,
      items: [
        'Aadhaar ending 4821',
        'Your Aadhaar number is used only for this e-sign',
      ],
      action: 'Send Aadhaar OTP',
    ),
    JourneyStep(
      title: 'Enter the signing OTP',
      subtitle: 'The code works for 5 minutes.',
      icon: Icons.password_rounded,
      items: ['6-digit OTP sent to your Aadhaar-linked phone'],
      note:
          'OTP not coming? Use your TrustKeyper phone OTP and draw your signature. The team will check it.',
      action: 'Sign agreement',
    ),
    JourneyStep(
      title: 'Agreement signed',
      subtitle: 'Your signature is complete. We are waiting for the others.',
      icon: Icons.verified_rounded,
      items: ['Signed by Rajesh Kumar', 'Copy sent on WhatsApp and email'],
      tone: JourneyTone.success,
      action: 'Done',
    ),
  ];

  static const brokerSigningProgress = [
    JourneyStep(
      title: 'Everyone said yes',
      subtitle: 'All 4 people approved the agreement.',
      icon: Icons.groups_2_outlined,
      items: [
        'Rajesh Kumar · said yes',
        'Sunita Devi · said yes',
        'Priya Sharma · said yes',
        'Rahul Verma · said yes',
      ],
      action: 'Send for signing',
      tone: JourneyTone.success,
    ),
    JourneyStep(
      title: 'Getting the agreement ready',
      subtitle: 'The TrustKeyper team handles these steps.',
      icon: Icons.print_outlined,
      items: [
        'Request received',
        'Buying Telangana stamp paper',
        'Printing the agreement',
        'Final check',
        'Send to everyone to sign',
      ],
      action: 'See signing status',
    ),
    JourneyStep(
      title: 'Signed by all 4',
      subtitle: 'The signed PDF is available to everyone.',
      icon: Icons.task_alt_rounded,
      items: ['Signed agreement saved', 'Copies sent on WhatsApp and email'],
      action: 'Start move-in',
      tone: JourneyTone.success,
    ),
  ];

  static const moveIn = [
    JourneyStep(
      title: 'Move-in checklist',
      subtitle: 'Finish each item at the property.',
      icon: Icons.checklist_rounded,
      items: [
        'Deposit and first rent',
        'Photos of every room and fixture',
        'Meter photos and readings',
        'Hand over keys with tenant OTP',
      ],
      action: 'Start checklist',
    ),
    JourneyStep(
      title: 'Deposit and first rent',
      subtitle: 'Keys stay with you until every tenant has paid.',
      icon: Icons.payments_outlined,
      amountLabel: 'Total received',
      amount: '₹66,000',
      amountWords: 'Sixty-six thousand rupees',
      items: ['Deposit ₹44,000 · paid', 'October rent ₹22,000 · paid'],
      action: 'Take move-in photos',
    ),
    JourneyStep(
      title: 'Take stamped photos',
      subtitle: 'Photograph every room and item before handing over keys.',
      icon: Icons.add_a_photo_outlined,
      items: [
        'Living room · 12 photos',
        'Kitchen · 10 photos',
        'Bedroom 1 · 14 photos',
        'Bedroom 2 · 14 photos',
        'Bathrooms and fixtures · 14 photos',
      ],
      note: 'Every photo carries date, time, Rahul Sharma and Broker.',
      action: 'Add meter readings',
    ),
    JourneyStep(
      title: 'Meter readings',
      subtitle: 'Take a photo and enter the number shown.',
      icon: Icons.speed_outlined,
      items: ['Electricity · 18,642 units', 'Water · 03,812 units'],
      action: 'Hand over keys',
    ),
    JourneyStep(
      title: 'Hand over keys',
      subtitle: 'Priya confirms the keys with an OTP.',
      icon: Icons.key_outlined,
      items: ['Main door · 2 keys', 'Bedroom · 2 keys', 'Mailbox · 1 key'],
      action: 'Verify tenant OTP',
    ),
    JourneyStep(
      title: 'Moved in',
      subtitle: 'Phoenix Towers 402 is now marked Rented.',
      icon: Icons.home_rounded,
      amountLabel: 'Brokerage on the way',
      amount: '₹33,000',
      amountWords: 'Thirty-three thousand rupees',
      note: 'Brokerage reaches your bank about 2 days after move-in.',
      action: 'Back to home',
      tone: JourneyTone.success,
    ),
  ];

  static const tenantSetup = [
    JourneyStep(
      title: 'Welcome home, Priya',
      subtitle: 'Your broker added Phoenix Towers 402.',
      icon: Icons.home_outlined,
      items: ['Owner · Rajesh Kumar and Sunita Devi', 'Broker · Rahul Sharma'],
      action: 'Yes, this is my home',
    ),
    JourneyStep(
      title: 'Your flatmates',
      subtitle: 'These names are on the agreement.',
      icon: Icons.group_outlined,
      items: ['Priya Sharma · you', 'Rahul Verma · flatmate'],
      action: 'These are correct',
    ),
    JourneyStep(
      title: 'Your rent share',
      subtitle: 'Check the split before your first payment.',
      icon: Icons.currency_rupee_rounded,
      amountLabel: 'You pay every month',
      amount: '₹11,000',
      amountWords: 'Eleven thousand rupees',
      items: ['Total home rent ₹22,000', 'Your deposit share ₹22,000'],
      action: 'My share is correct',
    ),
    JourneyStep(
      title: 'Your home is ready',
      subtitle: 'Payments, receipts, repairs and photos stay here.',
      icon: Icons.check_circle_outline_rounded,
      tone: JourneyTone.success,
      action: 'Go to home',
    ),
  ];

  static const tenantFirstPayment = [
    JourneyStep(
      title: 'First payment',
      subtitle: 'Only this month, deposit and maintenance are due now.',
      icon: Icons.receipt_long_outlined,
      amountLabel: 'Total to pay',
      amount: '₹33,000',
      amountWords: 'Thirty-three thousand rupees',
      items: [
        'Deposit share ₹22,000',
        'October rent ₹11,000',
        'Maintenance ₹0',
      ],
      action: 'Choose how to pay',
    ),
    JourneyStep(
      title: 'Pay safely',
      subtitle: 'TrustKeyper never sees your UPI PIN.',
      icon: Icons.account_balance_wallet_outlined,
      items: ['Open a UPI app', 'Enter a UPI ID', 'Card or net banking'],
      action: 'Pay with UPI',
    ),
    JourneyStep(
      title: 'Payment complete',
      subtitle: 'Your receipt is on WhatsApp and email.',
      icon: Icons.check_circle_rounded,
      amountLabel: 'Paid',
      amount: '₹33,000',
      amountWords: 'Thirty-three thousand rupees',
      tone: JourneyTone.success,
      action: 'Done',
    ),
  ];

  static const tenantRepair = [
    JourneyStep(
      title: 'What needs fixing?',
      subtitle: 'Pick the closest option.',
      icon: Icons.home_repair_service_outlined,
      items: [
        'Water',
        'Electricity',
        'Appliance',
        'Door or lock',
        'Something else',
      ],
      action: 'Add a photo',
    ),
    JourneyStep(
      title: 'Show us the problem',
      subtitle: 'Add one clear photo and a few words.',
      icon: Icons.add_a_photo_outlined,
      items: ['Geyser is not heating water', 'Photo added · bathroom geyser'],
      action: 'Send issue',
    ),
    JourneyStep(
      title: 'We will call you today',
      subtitle: 'Issue TK-2048 has been sent to the team.',
      icon: Icons.support_agent_outlined,
      items: [
        'Owner approval is needed above ₹2,000',
        'Urgent? Call 9 am to 8 pm',
      ],
      action: 'Done',
      tone: JourneyTone.success,
    ),
  ];

  static const moveOutTenant = [
    JourneyStep(
      title: 'Give move-out notice',
      subtitle: 'Your agreement needs 1 month notice.',
      icon: Icons.logout_rounded,
      items: [
        'Earliest move-out date · 31 July 2027',
        'Tell us why you are leaving',
      ],
      action: 'Send notice',
    ),
    JourneyStep(
      title: 'Notice sent',
      subtitle: 'The owner, broker and TrustKeyper team have been told.',
      icon: Icons.mark_email_read_outlined,
      items: [
        'Pay the last rent and bills',
        'Book the move-out check',
        'Return every key',
      ],
      action: 'Book move-out check',
      tone: JourneyTone.success,
    ),
    JourneyStep(
      title: 'Check the deductions',
      subtitle: 'Each item includes move-in and move-out photos.',
      icon: Icons.fact_check_outlined,
      amountLabel: 'Total deductions',
      amount: '₹5,840',
      amountWords: 'Five thousand eight hundred forty rupees',
      items: [
        'Paint ₹3,500',
        'Chimney cleaning ₹800',
        'Missing key ₹300',
        'Electricity bill ₹1,240',
      ],
      action: 'I agree',
    ),
    JourneyStep(
      title: 'Choose refund bank',
      subtitle: 'TrustKeyper sends the rest within 7 days.',
      icon: Icons.account_balance_outlined,
      amountLabel: 'Deposit refund',
      amount: '₹19,080',
      amountWords: 'Nineteen thousand eighty rupees',
      items: ['HDFC Bank · ending 4821'],
      action: 'Confirm bank',
    ),
    JourneyStep(
      title: 'Deposit refunded',
      subtitle: 'Your move-out is complete.',
      icon: Icons.check_circle_rounded,
      amountLabel: 'Refunded',
      amount: '₹19,080',
      amountWords: 'Nineteen thousand eighty rupees',
      action: 'Done',
      tone: JourneyTone.success,
    ),
  ];

  static const brokerMoveOut = [
    JourneyStep(
      title: 'Tenant gave notice',
      subtitle: 'Priya plans to leave on 31 July 2027.',
      icon: Icons.notification_important_outlined,
      items: ['1-month notice is valid', 'Owner and team are informed'],
      action: 'Start move-out checklist',
    ),
    JourneyStep(
      title: 'Compare every room',
      subtitle: 'Use the stamped move-in photos as the record.',
      icon: Icons.compare_outlined,
      items: ['Living room', 'Kitchen', 'Bedroom 1', 'Bedroom 2', 'Bathrooms'],
      action: 'Add repairs',
    ),
    JourneyStep(
      title: 'Final readings and keys',
      subtitle: 'Count everything before the tenant leaves.',
      icon: Icons.key_outlined,
      items: [
        'Electricity 19,922 units',
        'Water 04,162 units',
        '5 keys returned · tenant OTP confirmed',
      ],
      action: 'Send deductions',
    ),
    JourneyStep(
      title: 'Deductions sent',
      subtitle: 'The owner decides today. TrustKeyper refunds the rest.',
      icon: Icons.receipt_long_outlined,
      amountLabel: 'Suggested deductions',
      amount: '₹5,840',
      amountWords: 'Five thousand eight hundred forty rupees',
      action: 'Finish move-out',
    ),
    JourneyStep(
      title: 'Move-out done',
      subtitle: 'Phoenix Towers 402 is now marked Empty.',
      icon: Icons.home_work_outlined,
      items: ['Repairs booked from the deposit', 'Owner can find a new tenant'],
      action: 'Back to home',
      tone: JourneyTone.success,
    ),
  ];

  static const ownerMoveOut = [
    JourneyStep(
      title: 'Priya gave move-out notice',
      subtitle: 'She plans to leave Phoenix Towers 402 on 31 July 2027.',
      icon: Icons.logout_rounded,
      items: [
        'The 1-month notice is valid',
        'Broker and TrustKeyper team are informed',
      ],
      action: 'See move-out check',
    ),
    JourneyStep(
      title: 'Review the deductions',
      subtitle: 'Decide today so the remaining deposit can be refunded.',
      icon: Icons.fact_check_outlined,
      amountLabel: 'Suggested deductions',
      amount: '₹5,840',
      amountWords: 'Five thousand eight hundred forty rupees',
      items: [
        'Paint ₹3,500',
        'Chimney cleaning ₹800',
        'Missing key ₹300',
        'Electricity bill ₹1,240',
      ],
      action: 'Approve deductions',
    ),
    JourneyStep(
      title: 'Deductions approved',
      subtitle: 'TrustKeyper will refund the tenant within 7 days.',
      icon: Icons.verified_rounded,
      items: ['₹5,840 kept for bills and repairs', '₹19,080 returned to Priya'],
      action: 'Done',
      tone: JourneyTone.success,
    ),
  ];

  static const brokerLateRent = [
    JourneyStep(
      title: 'Priya has not paid rent',
      subtitle: 'It is 4 October. Call her today and save what she says.',
      icon: Icons.phone_in_talk_outlined,
      amountLabel: 'Rent due',
      amount: '₹11,000',
      amountWords: 'Eleven thousand rupees',
      items: ['Rahul Verma has already paid', 'No late fee is added'],
      action: 'Call tenant',
      tone: JourneyTone.danger,
    ),
    JourneyStep(
      title: 'What did Priya say?',
      subtitle: 'Saving this stops the daily phone alert.',
      icon: Icons.edit_note_rounded,
      items: [
        'Will pay today',
        'Needs a few days',
        'Paid already',
        'Could not reach',
      ],
      action: 'Needs a few days',
    ),
    JourneyStep(
      title: 'Is the owner informed?',
      subtitle: 'Tell the owner before extending the last date.',
      icon: Icons.verified_user_outlined,
      items: ['I spoke to Rajesh Kumar', 'New last date · 12 October'],
      action: 'Give more time',
      tone: JourneyTone.warning,
    ),
    JourneyStep(
      title: 'More time given',
      subtitle: 'Priya now sees 12 October as the last date.',
      icon: Icons.event_available_outlined,
      action: 'Done',
      tone: JourneyTone.success,
    ),
  ];
}
