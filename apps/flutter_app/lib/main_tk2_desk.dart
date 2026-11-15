import 'main_tk2.dart' as broker;
import 'main_tk2_web.dart' as customer;

/// One web address for all three people (lead desk build):
/// - a tenant or owner link (#p-…, #l-…, #owner-…, #i-…, #deal-…, #d-…) opens
///   the tenant/owner web app, exactly as on the TK2 staging site;
/// - anything else opens the broker app, with the lead desk on a laptop.
/// Build: tool/build_tkdesk.sh. See docs/TRUSTKEEPER2-DESK.md.
Future<void> main() {
  final f = Uri.base.fragment;
  final isCustomerLink = RegExp(r'^(p|l|owner|i|deal|d)-').hasMatch(f);
  return isCustomerLink ? customer.main() : broker.main();
}
