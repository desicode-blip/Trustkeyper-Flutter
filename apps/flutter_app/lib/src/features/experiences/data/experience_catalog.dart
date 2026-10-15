import 'package:flutter/material.dart';

import '../../journeys/presentation/guided_journey_screen.dart';

class ExperienceDefinition {
  const ExperienceDefinition({
    required this.id,
    required this.page,
    required this.title,
    required this.audience,
    required this.description,
    required this.icon,
    required this.steps,
    this.archived = false,
  });

  final String id;
  final int page;
  final String title;
  final String audience;
  final String description;
  final IconData icon;
  final List<JourneyStep> steps;
  final bool archived;
}

abstract final class ExperienceCatalog {
  static ExperienceDefinition? byId(String id) {
    for (final experience in all) {
      if (experience.id == id) return experience;
    }
    return null;
  }

  static const all = <ExperienceDefinition>[
    ExperienceDefinition(
      id: 'admin-operations',
      page: 1,
      title: 'Admin operations',
      audience: 'Admin',
      description: 'Approvals, agreements, rent, payouts, repairs and checks.',
      icon: Icons.admin_panel_settings_outlined,
      steps: [
        JourneyStep(
          title: 'Operations dashboard',
          subtitle: 'Everything requiring the TrustKeyper team today.',
          icon: Icons.dashboard_outlined,
          items: [
            '3 broker approvals',
            '2 documents need another upload',
            '1 failed payout',
            '4 photo checks to review',
          ],
          choices: ['Broker approvals', 'Agreements', 'Payouts', 'Repairs'],
          action: 'Open queue',
        ),
        JourneyStep(
          title: 'Review the person',
          subtitle: 'Approve only after identity and business checks.',
          icon: Icons.badge_outlined,
          items: ['PAN checked', 'Phone verified', 'Business proof checked'],
          choices: ['Approve', 'Ask for document', 'Reject'],
          note: 'Every decision is recorded with the admin account and time.',
          action: 'Save decision',
        ),
        JourneyStep(
          title: 'Resolve the payout',
          subtitle: 'Check the bank response before retrying.',
          icon: Icons.account_balance_outlined,
          fields: [
            JourneyField(
              label: 'Internal note',
              type: JourneyFieldType.multiline,
            ),
          ],
          choices: ['Retry payout', 'Ask owner to update bank', 'Escalate'],
          action: 'Update payout',
        ),
        JourneyStep(
          title: 'Queue updated',
          subtitle: 'The decision is ready to sync with the operations API.',
          icon: Icons.task_alt_rounded,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'common-auth',
      page: 2,
      title: 'Welcome, login and signup',
      audience: 'Everyone',
      description: 'Four welcome screens, phone login, OTP, profile and role.',
      icon: Icons.login_rounded,
      steps: [],
    ),
    ExperienceDefinition(
      id: 'broker-new-agreement',
      page: 3,
      title: 'New agreement',
      audience: 'Broker',
      description: 'Property, owners, documents, rooms and agreement type.',
      icon: Icons.note_add_outlined,
      steps: [],
    ),
    ExperienceDefinition(
      id: 'owner-bank-send-link',
      page: 4,
      title: 'Owner bank, UPI and secure link',
      audience: 'Broker',
      description: 'Validate payout details and send owner upload links.',
      icon: Icons.account_balance_outlined,
      steps: [
        JourneyStep(
          title: 'Where should rent go?',
          subtitle: 'The account name must match a legal owner.',
          icon: Icons.account_balance_outlined,
          fields: [
            JourneyField(label: 'Account holder name'),
            JourneyField(
              label: 'Account number',
              type: JourneyFieldType.number,
            ),
            JourneyField(
              label: 'Confirm account number',
              type: JourneyFieldType.number,
            ),
            JourneyField(label: 'IFSC code'),
          ],
          action: 'Check bank account',
        ),
        JourneyStep(
          title: 'Or verify a UPI ID',
          subtitle: 'Use the owner’s UPI ID or scan their QR.',
          icon: Icons.qr_code_2_rounded,
          fields: [JourneyField(label: 'UPI ID', hint: 'name@bank')],
          attachment: JourneyAttachment.photo,
          action: 'Verify UPI',
        ),
        JourneyStep(
          title: 'Send a secure owner link',
          subtitle: 'Choose how Rajesh should receive the request.',
          icon: Icons.send_to_mobile_outlined,
          choices: ['WhatsApp', 'SMS', 'Both'],
          fields: [
            JourneyField(
              label: 'Owner mobile number',
              initialValue: '9988776655',
              type: JourneyFieldType.phone,
            ),
          ],
          action: 'Send secure link',
        ),
        JourneyStep(
          title: 'Link sent',
          subtitle: 'Rajesh can add documents without installing the app.',
          icon: Icons.mark_email_read_outlined,
          items: ['Link expires in 7 days', 'You can resend after 2 minutes'],
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'tenant-details-brokerage',
      page: 5,
      title: 'Tenants, agreement details and brokerage',
      audience: 'Broker',
      description: 'Tenant KYC, money, dates, notice and brokerage split.',
      icon: Icons.groups_outlined,
      steps: [
        JourneyStep(
          title: 'Who will live here?',
          subtitle: 'Add every tenant named on the agreement.',
          icon: Icons.groups_outlined,
          fields: [
            JourneyField(label: 'Tenant full name'),
            JourneyField(label: 'Mobile number', type: JourneyFieldType.phone),
          ],
          attachment: JourneyAttachment.document,
          action: 'Add tenant',
        ),
        JourneyStep(
          title: 'Rent, maintenance and deposit',
          subtitle: 'Enter totals for the entire property.',
          icon: Icons.currency_rupee_rounded,
          fields: [
            JourneyField(label: 'Monthly rent', type: JourneyFieldType.number),
            JourneyField(
              label: 'Maintenance',
              type: JourneyFieldType.number,
              required: false,
            ),
            JourneyField(
              label: 'Security deposit',
              type: JourneyFieldType.number,
            ),
          ],
          action: 'Save amounts',
        ),
        JourneyStep(
          title: 'Dates, lock-in and notice',
          subtitle: 'These details appear in the legal agreement.',
          icon: Icons.calendar_month_outlined,
          fields: [
            JourneyField(label: 'Agreement start', type: JourneyFieldType.date),
            JourneyField(label: 'Rent due day', type: JourneyFieldType.number),
          ],
          choices: ['6-month lock-in', 'No lock-in', 'Custom'],
          action: 'Save dates',
        ),
        JourneyStep(
          title: 'Who pays brokerage?',
          subtitle: 'Show the owner and tenant shares separately.',
          icon: Icons.payments_outlined,
          choices: ['Owner', 'Tenant', 'Both'],
          fields: [
            JourneyField(
              label: 'Total brokerage',
              type: JourneyFieldType.number,
            ),
          ],
          action: 'Save brokerage',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'review-edit-send',
      page: 6,
      title: 'Review, edit and send',
      audience: 'Broker',
      description: 'Review all details, resolve errors and send secure links.',
      icon: Icons.fact_check_outlined,
      steps: [
        JourneyStep(
          title: 'Check everything',
          subtitle: 'Nothing is sent until you confirm each section.',
          icon: Icons.fact_check_outlined,
          items: [
            'Phoenix Towers 402 · 2 BHK',
            '2 owners · 2 tenants',
            '₹22,000 rent · ₹44,000 deposit',
            '₹33,000 total brokerage',
          ],
          confirmationLabel: 'I checked all names, amounts and dates',
          action: 'Preview agreement',
        ),
        JourneyStep(
          title: 'Preview agreement',
          subtitle: 'The final PDF will use these approved details.',
          icon: Icons.picture_as_pdf_outlined,
          items: [
            '4 pages',
            '11-month term',
            '6-month lock-in',
            '1-month notice',
          ],
          choices: ['Everything is correct', 'Go back and edit'],
          action: 'Continue',
        ),
        JourneyStep(
          title: 'Send to everyone?',
          subtitle: 'Each person gets their own secure link.',
          icon: Icons.send_rounded,
          confirmationLabel:
              'I understand changes after sending are shown to everyone',
          action: 'Send agreement',
        ),
        JourneyStep(
          title: 'Agreement sent',
          subtitle: 'Track who opened the link and who replied.',
          icon: Icons.mark_email_read_outlined,
          items: [
            'Rajesh · delivered',
            'Sunita · delivered',
            'Priya · opened',
            'Rahul · delivered',
          ],
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'signing-move-in',
      page: 7,
      title: 'Signing and move-in',
      audience: 'Broker',
      description: 'Stamp paper, signing, deposit, photos, meters and keys.',
      icon: Icons.key_outlined,
      steps: [
        JourneyStep(
          title: 'Everyone said yes',
          subtitle: 'TrustKeyper is preparing the stamp-paper copy.',
          icon: Icons.verified_outlined,
          items: [
            'Details locked',
            'Stamp paper ordered',
            'Signing links next',
          ],
          action: 'See signing steps',
        ),
        JourneyStep(
          title: 'Upload the stamped agreement',
          subtitle: 'Add every page in order after manual signing.',
          icon: Icons.document_scanner_outlined,
          attachment: JourneyAttachment.both,
          action: 'Save signed agreement',
        ),
        JourneyStep(
          title: 'Record move-in condition',
          subtitle: 'Take clear room, meter and key photos.',
          icon: Icons.camera_alt_outlined,
          attachment: JourneyAttachment.photo,
          choices: ['Living room', 'Bedroom', 'Kitchen', 'Meters', 'Keys'],
          action: 'Save photo',
        ),
        JourneyStep(
          title: 'Confirm with tenant OTP',
          subtitle: 'The tenant confirms the checklist at handover.',
          icon: Icons.password_rounded,
          fields: [
            JourneyField(label: 'Tenant OTP', type: JourneyFieldType.number),
          ],
          action: 'Complete move-in',
        ),
        JourneyStep(
          title: 'Move-in completed',
          subtitle: 'Agreement, money and home condition are recorded.',
          icon: Icons.home_rounded,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'renew-sign-only',
      page: 8,
      title: 'Renew or only get it signed',
      audience: 'Broker',
      description:
          'Renew an existing agreement or upload an outside agreement.',
      icon: Icons.autorenew_rounded,
      steps: [
        JourneyStep(
          title: 'What do you want to do?',
          subtitle: 'Start from TrustKeyper or upload an existing agreement.',
          icon: Icons.autorenew_rounded,
          choices: [
            'Renew TrustKeyper agreement',
            'Only get an agreement signed',
          ],
          action: 'Continue',
        ),
        JourneyStep(
          title: 'Choose or upload the agreement',
          subtitle: 'PDF and clear page photos are supported.',
          icon: Icons.upload_file_outlined,
          attachment: JourneyAttachment.both,
          action: 'Read agreement',
        ),
        JourneyStep(
          title: 'Check details we found',
          subtitle: 'Correct anything the document reader missed.',
          icon: Icons.fact_check_outlined,
          fields: [
            JourneyField(label: 'Property', initialValue: 'Phoenix Towers 402'),
            JourneyField(
              label: 'Monthly rent',
              initialValue: '22000',
              type: JourneyFieldType.number,
            ),
            JourneyField(label: 'New end date', type: JourneyFieldType.date),
          ],
          action: 'Save details',
        ),
        JourneyStep(
          title: 'Who signs?',
          subtitle: 'Add each owner and tenant exactly as written.',
          icon: Icons.draw_outlined,
          choices: ['Owners and tenants', 'Owners only', 'Tenants only'],
          action: 'Send to team',
        ),
        JourneyStep(
          title: 'Sent to the TrustKeyper team',
          subtitle: 'The manual signing fallback remains available.',
          icon: Icons.task_alt_rounded,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'broker-records-payments-profile',
      page: 9,
      title: 'Agreements, records, payments and profile',
      audience: 'Broker',
      description: 'The complete five-tab broker workspace.',
      icon: Icons.space_dashboard_outlined,
      steps: [
        JourneyStep(
          title: 'Broker workspace',
          subtitle:
              'Open every agreement, person, property and payment record.',
          icon: Icons.space_dashboard_outlined,
          choices: [
            'Agreements',
            'Properties',
            'Owners',
            'Tenants',
            'Payments',
          ],
          action: 'Open section',
        ),
        JourneyStep(
          title: 'Payout bank',
          subtitle: 'Brokerage is paid only to a verified bank account.',
          icon: Icons.account_balance_outlined,
          fields: [
            JourneyField(label: 'Account holder name'),
            JourneyField(
              label: 'Account number',
              type: JourneyFieldType.number,
            ),
            JourneyField(label: 'IFSC code'),
          ],
          action: 'Verify bank',
        ),
        JourneyStep(
          title: 'Verify bank change',
          subtitle: 'Enter the OTP sent to your registered phone.',
          icon: Icons.password_outlined,
          fields: [JourneyField(label: 'OTP', type: JourneyFieldType.number)],
          action: 'Change bank',
        ),
        JourneyStep(
          title: 'Profile updated',
          subtitle: 'The new payout bank is active.',
          icon: Icons.verified_rounded,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'owner-links-documents',
      page: 10,
      title: 'Owner links and documents',
      audience: 'Owner',
      description: 'Secure web links, identity files and upload progress.',
      icon: Icons.link_rounded,
      steps: [
        JourneyStep(
          title: 'Rahul asked for your documents',
          subtitle: 'Phoenix Towers 402 · secure link expires in 7 days.',
          icon: Icons.link_rounded,
          items: [
            'Your phone must match the agreement',
            'Files are visible to the TrustKeyper team',
          ],
          action: 'Add documents',
        ),
        JourneyStep(
          title: 'Add identity and ownership documents',
          subtitle: 'Choose a PDF or take clear photos.',
          icon: Icons.badge_outlined,
          choices: ['Aadhaar', 'PAN', 'Sale deed', 'Latest tax receipt'],
          attachment: JourneyAttachment.both,
          action: 'Save document',
        ),
        JourneyStep(
          title: 'Documents sent',
          subtitle: 'Rahul and TrustKeyper can now check them.',
          icon: Icons.cloud_done_outlined,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'owner-home-money-issues',
      page: 11,
      title: 'Owner home, money, issues and photo checks',
      audience: 'Owner',
      description:
          'Properties, payouts, repair approvals and condition photos.',
      icon: Icons.home_work_outlined,
      steps: [
        JourneyStep(
          title: 'Your property at a glance',
          subtitle: 'Phoenix Towers 402 · Priya and Rahul.',
          icon: Icons.home_work_outlined,
          items: [
            'Rent ₹22,000',
            'Next payout 7 Nov',
            'Agreement active',
            '1 repair needs approval',
          ],
          choices: ['Money', 'Issues', 'Agreement', 'Photo checks'],
          action: 'Open section',
        ),
        JourneyStep(
          title: 'Approve repair?',
          subtitle: 'Geyser is not heating · technician estimate attached.',
          icon: Icons.home_repair_service_outlined,
          amountLabel: 'Estimate',
          amount: '₹2,800',
          amountWords: 'Two thousand eight hundred rupees',
          attachment: JourneyAttachment.document,
          choices: ['Approve', 'Ask a question', 'Decline'],
          action: 'Save decision',
        ),
        JourneyStep(
          title: 'Compare home photos',
          subtitle: 'See the move-in photo beside the latest photo.',
          icon: Icons.compare_outlined,
          choices: ['Living room', 'Bedroom', 'Kitchen', 'Bathroom'],
          action: 'Mark checked',
        ),
        JourneyStep(
          title: 'Owner action saved',
          subtitle: 'The tenant, broker and team can see the update.',
          icon: Icons.task_alt_rounded,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'tenant-home-payments-issues',
      page: 12,
      title: 'Tenant home, payments and issues',
      audience: 'Tenant',
      description: 'Home setup, rent share, payment, repairs and profile.',
      icon: Icons.home_outlined,
      steps: [
        JourneyStep(
          title: 'Confirm your home',
          subtitle: 'Phoenix Towers 402 · Rahul sent this invitation.',
          icon: Icons.home_outlined,
          choices: ['This is my home', 'This is not my home'],
          action: 'Continue',
        ),
        JourneyStep(
          title: 'Confirm your rent share',
          subtitle: 'The total rent is ₹22,000 for two tenants.',
          icon: Icons.group_outlined,
          fields: [
            JourneyField(
              label: 'Your monthly share',
              initialValue: '11000',
              type: JourneyFieldType.number,
            ),
          ],
          confirmationLabel: 'My share is correct',
          action: 'Save share',
        ),
        JourneyStep(
          title: 'What needs fixing?',
          subtitle: 'A photo helps the owner approve the work faster.',
          icon: Icons.home_repair_service_outlined,
          fields: [
            JourneyField(
              label: 'Describe the problem',
              type: JourneyFieldType.multiline,
            ),
          ],
          attachment: JourneyAttachment.photo,
          action: 'Raise issue',
        ),
        JourneyStep(
          title: 'Home ready',
          subtitle: 'Rent, agreement and repairs are available from your tabs.',
          icon: Icons.task_alt_rounded,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'archive-broker-steps',
      page: 13,
      title: 'Discarded broker steps',
      audience: 'Archive',
      description: 'Older artboards retained only for design history.',
      icon: Icons.archive_outlined,
      archived: true,
      steps: [],
    ),
    ExperienceDefinition(
      id: 'archive-review-options',
      page: 14,
      title: 'Discarded review and options',
      audience: 'Archive',
      description: 'Superseded review artboards, not part of the shipped app.',
      icon: Icons.archive_outlined,
      archived: true,
      steps: [],
    ),
    ExperienceDefinition(
      id: 'approve-and-sign',
      page: 15,
      title: 'Say yes and sign',
      audience: 'Owner & tenant',
      description: 'Review, request a change, approve and complete signing.',
      icon: Icons.draw_outlined,
      steps: [
        JourneyStep(
          title: 'Rahul sent your agreement',
          subtitle: 'Check your name, money and dates before saying yes.',
          icon: Icons.description_outlined,
          items: [
            'Rent ₹22,000',
            'Deposit ₹44,000',
            'Starts 1 Oct 2026',
            'Ends 31 Aug 2027',
          ],
          choices: ['Everything is correct', 'Request a change'],
          action: 'Continue',
        ),
        JourneyStep(
          title: 'Confirm your approval',
          subtitle: 'You can still see the agreement after approving.',
          icon: Icons.verified_user_outlined,
          confirmationLabel:
              'I read the full agreement and the details are correct',
          action: 'Yes, I agree',
        ),
        JourneyStep(
          title: 'Sign with Aadhaar OTP',
          subtitle: 'Use the OTP sent by the signing provider.',
          icon: Icons.password_outlined,
          fields: [
            JourneyField(label: 'Aadhaar OTP', type: JourneyFieldType.number),
          ],
          action: 'Sign agreement',
        ),
        JourneyStep(
          title: 'You signed',
          subtitle: 'We will tell you when everyone has signed.',
          icon: Icons.verified_rounded,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'move-out',
      page: 16,
      title: 'Move-out',
      audience: 'Tenant, owner, broker & admin',
      description: 'Notice, inspection, deductions, dispute and refund.',
      icon: Icons.logout_rounded,
      steps: [
        JourneyStep(
          title: 'When will you move out?',
          subtitle: 'Your agreement requires one month notice.',
          icon: Icons.event_outlined,
          fields: [
            JourneyField(label: 'Move-out date', type: JourneyFieldType.date),
            JourneyField(
              label: 'Reason',
              type: JourneyFieldType.multiline,
              required: false,
            ),
          ],
          action: 'Send notice',
        ),
        JourneyStep(
          title: 'Book the inspection',
          subtitle: 'Tenant, owner and broker will see the slot.',
          icon: Icons.calendar_month_outlined,
          choices: ['10 am – 12 pm', '2 pm – 4 pm', '5 pm – 7 pm'],
          action: 'Book inspection',
        ),
        JourneyStep(
          title: 'Record final condition',
          subtitle: 'Add room, meter and key photos.',
          icon: Icons.camera_alt_outlined,
          choices: ['Rooms', 'Meters', 'Keys', 'Bills'],
          attachment: JourneyAttachment.both,
          action: 'Save evidence',
        ),
        JourneyStep(
          title: 'Check deductions',
          subtitle: 'Compare every amount with photos or a bill.',
          icon: Icons.receipt_long_outlined,
          amountLabel: 'Suggested deductions',
          amount: '₹5,840',
          amountWords: 'Five thousand eight hundred forty rupees',
          choices: ['Agree', 'Ask a question', 'Dispute'],
          action: 'Send response',
        ),
        JourneyStep(
          title: 'Refund scheduled',
          subtitle:
              'The remaining deposit will reach the tenant within 7 days.',
          icon: Icons.currency_rupee_rounded,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'owner-self-onboarding',
      page: 17,
      title: 'Owner self-onboarding',
      audience: 'Owner',
      description: 'Add a property, choose a plan and start management.',
      icon: Icons.add_home_work_outlined,
      steps: [
        JourneyStep(
          title: 'What do you want help with?',
          subtitle: 'Choose the service for this property.',
          icon: Icons.add_home_work_outlined,
          choices: [
            'Manage a rented home',
            'Find a tenant',
            'Create an agreement',
            'Sell property',
          ],
          action: 'Continue',
        ),
        JourneyStep(
          title: 'Tell us about the property',
          subtitle: 'Add the address exactly as used on ownership papers.',
          icon: Icons.location_on_outlined,
          fields: [
            JourneyField(label: 'Property name'),
            JourneyField(label: 'Address', type: JourneyFieldType.multiline),
            JourneyField(label: 'PIN code', type: JourneyFieldType.number),
          ],
          action: 'Save property',
        ),
        JourneyStep(
          title: 'Rooms, things and photos',
          subtitle: 'This becomes the home-condition record.',
          icon: Icons.photo_camera_back_outlined,
          choices: ['1 BHK', '2 BHK', '3 BHK', 'Other'],
          attachment: JourneyAttachment.photo,
          action: 'Save home details',
        ),
        JourneyStep(
          title: 'Choose your plan',
          subtitle: 'Compare help with rent, repairs and tenant finding.',
          icon: Icons.workspace_premium_outlined,
          choices: [
            'Free check',
            'Rent management',
            'Find a tenant',
            'Talk to manager',
          ],
          action: 'Choose plan',
        ),
        JourneyStep(
          title: 'Property setup started',
          subtitle: 'Your manager will contact you if the plan needs a call.',
          icon: Icons.task_alt_rounded,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
    ExperienceDefinition(
      id: 'late-rent',
      page: 18,
      title: 'Late rent',
      audience: 'Tenant, owner, broker & admin',
      description: 'Reminders, partial payment, calls, notices and more time.',
      icon: Icons.warning_amber_rounded,
      steps: [
        JourneyStep(
          title: 'Rent is 3 days late',
          subtitle:
              'No late fee. Please pay today so the owner gets rent on time.',
          icon: Icons.warning_amber_rounded,
          amountLabel: 'November rent',
          amount: '₹11,000',
          amountWords: 'Eleven thousand rupees',
          choices: ['Pay in full', 'Pay part now', 'Talk to us'],
          action: 'Continue',
          tone: JourneyTone.warning,
        ),
        JourneyStep(
          title: 'Pay part and promise the rest',
          subtitle: 'The owner and team see the date you choose.',
          icon: Icons.payments_outlined,
          fields: [
            JourneyField(
              label: 'Pay now',
              initialValue: '5000',
              type: JourneyFieldType.number,
            ),
            JourneyField(label: 'Pay rest on', type: JourneyFieldType.date),
          ],
          action: 'Continue to payment',
        ),
        JourneyStep(
          title: 'What did the tenant say?',
          subtitle: 'Saving this stops the broker’s daily call alert.',
          icon: Icons.phone_in_talk_outlined,
          choices: [
            'Will pay today',
            'Will pay on a date',
            'Needs help',
            'Did not pick up',
          ],
          action: 'Save call outcome',
        ),
        JourneyStep(
          title: 'Give more time?',
          subtitle: 'No notice goes before the new date.',
          icon: Icons.event_available_outlined,
          fields: [
            JourneyField(label: 'New last date', type: JourneyFieldType.date),
          ],
          choices: ['Salary late', 'Medical', 'Trusted tenant', 'Other'],
          confirmationLabel: 'The owner has been informed',
          action: 'Give more time',
        ),
        JourneyStep(
          title: 'New date shared',
          subtitle: 'Tenant, owner, broker and team can see the extension.',
          icon: Icons.task_alt_rounded,
          tone: JourneyTone.success,
          action: 'Done',
        ),
      ],
    ),
  ];
}
