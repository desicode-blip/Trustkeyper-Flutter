typedef ExperienceEntry = ({String label, String route});

const implementedExperiences = <String, List<ExperienceEntry>>{
  'admin-operations': [(label: 'Open operations', route: '/admin')],
  'common-auth': [(label: 'Open onboarding and login', route: '/onboarding')],
  'broker-new-agreement': [
    (label: 'Create an agreement', route: '/broker/agreement'),
  ],
  'owner-bank-send-link': [
    (
      label: 'Open saved agreements and document links',
      route: '/broker/unfinished',
    ),
  ],
  'tenant-details-brokerage': [
    (label: 'Open saved agreement details', route: '/broker/unfinished'),
  ],
  'review-edit-send': [
    (label: 'Review a saved agreement', route: '/broker/unfinished'),
  ],
  'signing-move-in': [
    (label: 'Agreement replies and signed copies', route: '/broker/signing'),
    (label: 'Move-in and key confirmation', route: '/broker/move-in'),
  ],
  'renew-sign-only': [
    (label: 'Renew a saved signed agreement', route: '/broker/renew'),
    (label: 'Upload an agreement for signing only', route: '/broker/sign-only'),
    (label: 'See actual signing-only progress', route: '/broker/signing-requests'),
  ],
  'broker-records-payments-profile': [
    (label: 'Open broker workspace', route: '/broker'),
  ],
  'owner-home-money-issues': [(label: 'Open owner workspace', route: '/owner')],
  'owner-self-onboarding': [
    (label: 'Add a property and request a plan', route: '/owner/onboarding'),
  ],
  'tenant-home-payments-issues': [
    (label: 'Open tenant workspace', route: '/tenant'),
  ],
  'approve-and-sign': [
    (label: 'Owner agreements and signed copies', route: '/owner/agreement'),
    (label: 'Tenant agreements and signed copies', route: '/tenant/agreement'),
  ],
  'move-out': [
    (label: 'Broker move-out', route: '/broker/move-out'),
    (label: 'Owner move-out', route: '/owner/move-out'),
    (label: 'Tenant move-out', route: '/tenant/move-out'),
  ],
  'late-rent': [
    (label: 'Broker rent follow-up', route: '/broker/late-rent'),
    (label: 'Owner rent follow-up', route: '/owner/late-rent'),
    (label: 'Tenant rent follow-up', route: '/tenant/late-rent'),
  ],
};
