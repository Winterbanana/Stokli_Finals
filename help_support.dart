import "package:flutter/material.dart";

class _FaqEntry {
  const _FaqEntry(
    this.category,
    this.question,
    this.answer, {
    this.adminOnly = false,
  });

  final String category;
  final String question;
  final String answer;
  final bool adminOnly;
}

const _faq = <_FaqEntry>[
  _FaqEntry(
    "Account",
    "How do I log in?",
    "Choose Student or Admin on the sign-in screen, enter the account ID and password for that role, then tap Sign in. An inactive account must be reactivated by an administrator.",
  ),
  _FaqEntry(
    "Account",
    "How do I edit my profile?",
    "Open Settings and choose Edit profile. You can update your name, email, contact number, and program or section. Account ID and role are controlled by the system.",
  ),
  _FaqEntry(
    "Account",
    "How do I upload or remove a profile photo?",
    "Open Settings, choose Edit profile, then select a photo from the gallery or camera. Review the preview and save. The app accepts JPG, PNG, or WEBP photos up to 1.5 MB. Choose Remove photo to clear the current photo.",
  ),
  _FaqEntry(
    "Account",
    "How do I change my password?",
    "Open Settings and choose Change password. Enter your current password and a new password twice. The new password needs at least 8 characters, including uppercase, lowercase, a number, and a symbol. An Internet connection is required.",
  ),
  _FaqEntry(
    "Account",
    "How do I log out?",
    "Use the menu in the top-right corner or the Sign out action in your account area.",
  ),
  _FaqEntry(
    "Equipment",
    "How do I view or search equipment?",
    "Open Inventory. Search by equipment name, ID/code, brand, model, category, serial number, or status. Scroll to load further records; select an item for its details.",
  ),
  _FaqEntry(
    "Equipment",
    "How do I check equipment availability?",
    "Open Inventory and check the availability and status shown on the equipment card or detail page. Items that cannot be borrowed remain visible, but the request action is unavailable.",
  ),
  _FaqEntry(
    "Equipment",
    "What do equipment statuses mean?",
    "Available means stock can be requested. Borrowed means at least one unit is out. Pending means a request is awaiting review. Overdue means a borrowing is past its due time. Damaged, Lost, Under Maintenance, and Retired indicate that the affected stock is not currently borrowable.",
  ),
  _FaqEntry(
    "Borrowing",
    "How do I request equipment?",
    "Open Inventory, select equipment with available stock, and submit a borrowing request. Track its Pending, Approved, or Rejected status under Requests. An approved request is completed with staff before collection.",
  ),
  _FaqEntry(
    "Borrowing",
    "What do Pending, Approved, and Rejected mean?",
    "Pending means staff have not decided yet. Approved means the request was accepted; follow the in-app instructions and coordinate collection with staff. Rejected means the request was not accepted.",
  ),
  _FaqEntry(
    "Returns",
    "How do I return equipment?",
    "Open Returns, choose the active borrowing, report the item condition, and submit it for staff review. The borrowing is not fully closed until staff verifies the return.",
  ),
  _FaqEntry(
    "Returns",
    "What happens if equipment is damaged or lost?",
    "Report the observed condition accurately during the return flow and submit it for staff inspection. Staff review exceptions and any applicable penalty; the help assistant cannot verify an individual case.",
  ),
  _FaqEntry(
    "Penalties & payments",
    "How is an overdue penalty calculated?",
    "The current configured system rule is ₱100 per overdue day. Check the Penalties section for the actual amount assessed on your account; the assistant cannot look up account balances.",
  ),
  _FaqEntry(
    "Penalties & payments",
    "How do I check my penalty or payment status?",
    "Students can open Profile to review their penalty and payment records. A submitted payment is a record for staff verification; it does not charge a wallet or settle a penalty until verified.",
  ),
  _FaqEntry(
    "Notifications",
    "How do notification preferences work?",
    "Open Settings to change notification preferences. In this build the choices are saved locally as preferences; push or scheduled notification delivery is not configured.",
  ),
  _FaqEntry(
    "Offline & synchronization",
    "What happens when I am offline?",
    "The app can show locally cached inventory and save supported actions on this device. A queued change is not yet confirmed by MySQL. Reconnect to the server and use Sync to send pending work.",
  ),
  _FaqEntry(
    "Offline & synchronization",
    "What does Synchronizing or Sync Failed mean?",
    "Synchronizing means queued operations are being sent to the server. A failed operation stays in the local queue and is not marked synced. Review the error, reconnect, and retry; a profile conflict requires refreshing the latest account values before deciding what to save.",
  ),
  _FaqEntry(
    "Settings",
    "How do I change the theme?",
    "Open Settings and choose Light, Dark, or System. The choice is saved for the signed-in account.",
  ),
  _FaqEntry(
    "Settings",
    "How do account settings work?",
    "Appearance and notification preferences are stored locally for the signed-in account. Profile changes synchronize through the API when online; password changes require Internet access.",
  ),
  _FaqEntry(
    "Admin",
    "How do I manage student accounts?",
    "Administrators can open Accounts to view the account directory and edit permitted Student profile fields or activate/suspend an account. Student IDs, roles, and permissions are protected.",
    adminOnly: true,
  ),
  _FaqEntry(
    "Admin",
    "How do I review borrowing, returns, payments, and activity?",
    "Use the corresponding Requests, Returns, Payments, and Activity tabs. Decisions and account changes are recorded in the activity log; passwords are never included.",
    adminOnly: true,
  ),
  _FaqEntry(
    "Admin",
    "How does account synchronization handle conflicts?",
    "Profile changes carry a server profile version and an idempotency key. If another edit changes the profile first, sync reports a conflict and retains the pending operation instead of silently overwriting the newer server data.",
    adminOnly: true,
  ),
];

class HelpSupportPage extends StatefulWidget {
  const HelpSupportPage({super.key, required this.isAdmin});

  final bool isAdmin;

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  final _searchController = TextEditingController();
  final _chatController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      isUser: false,
      text: "Hello. I can answer how-to questions using Stokli's built-in help. I cannot verify live account, borrowing, payment, or inventory records.",
    ),
  ];
  bool _answering = false;

  List<_FaqEntry> get _visibleFaq {
    final query = _searchController.text.trim().toLowerCase();
    return _faq.where((entry) {
      if (entry.adminOnly && !widget.isAdmin) return false;
      return query.isEmpty ||
          entry.category.toLowerCase().contains(query) ||
          entry.question.toLowerCase().contains(query) ||
          entry.answer.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _send([String? suggested]) async {
    final question = (suggested ?? _chatController.text).trim();
    if (question.isEmpty || _answering) return;
    _chatController.clear();
    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: question));
      _answering = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    final answer = _answerFor(question);
    setState(() {
      _messages.add(_ChatMessage(isUser: false, text: answer));
      _answering = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _answerFor(String question) {
    final normalized = question.toLowerCase();
    final tokens = normalized
        .replaceAll(RegExp(r"[^a-z0-9 ]"), " ")
        .split(RegExp(r"\s+"))
        .where((token) => token.length > 2)
        .toSet();
    var bestScore = 0;
    _FaqEntry? best;
    for (final entry in _faq) {
      if (entry.adminOnly && !widget.isAdmin) continue;
      final text = "${entry.question} ${entry.category} ${entry.answer}"
          .toLowerCase();
      var score = 0;
      for (final token in tokens) {
        if (text.contains(token)) score += token.length > 5 ? 2 : 1;
      }
      if (normalized.contains("photo") && entry.question.contains("photo")) {
        score += 6;
      }
      if (normalized.contains("borrow") && entry.category == "Borrowing") {
        score += 4;
      }
      if (normalized.contains("return") && entry.category == "Returns") {
        score += 4;
      }
      if (normalized.contains("penalt") &&
          entry.category == "Penalties & payments") {
        score += 4;
      }
      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }
    if (best == null || bestScore < 2) {
      return "I can only answer how-to questions covered by the built-in Stokli help. I cannot verify individual records or account status. Try the FAQ tab or ask about Inventory, borrowing, returns, profiles, passwords, payments, offline sync, or Settings. If you still need help, contact your system administrator through your institution's usual support channel.";
    }
    return "${best.answer}\n\nFor privacy, I do not look up account-specific records. Open the relevant page in Stokli to check live information.";
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _visibleFaq.map((entry) => entry.category).toSet();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Help & Support"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "FAQ", icon: Icon(Icons.help_outline)),
              Tab(
                text: "Chat support",
                icon: Icon(Icons.support_agent_outlined),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: "Search help topics",
                      suffixIcon: IconButton(
                        tooltip: "Clear search",
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: categories.isEmpty
                      ? const Center(child: Text("No matching help topics."))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          children: [
                            for (final category in categories)
                              Card(
                                clipBehavior: Clip.antiAlias,
                                child: ExpansionTile(
                                  title: Text(
                                    category,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  children: [
                                    for (final entry in _visibleFaq.where(
                                      (entry) => entry.category == category,
                                    ))
                                      ExpansionTile(
                                        title: Text(entry.question),
                                        childrenPadding:
                                            const EdgeInsets.fromLTRB(
                                              16,
                                              0,
                                              16,
                                              16,
                                            ),
                                        children: [
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(entry.answer),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                "Help is available offline. Account-specific values must be checked in the app and are not provided by this assistant.",
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
            Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: const Text(
                    "Grounded in Stokli's built-in help; no external AI service or account records are accessed.",
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length + (_answering ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const ListTile(
                          leading: CircleAvatar(
                            child: Icon(Icons.support_agent_outlined),
                          ),
                          title: Text("Checking the help guide…"),
                        );
                      }
                      final message = _messages[index];
                      return Align(
                        alignment: message.isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 340),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(message.text),
                        ),
                      );
                    },
                  ),
                ),
                if (_messages.length == 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 7,
                      children:
                          [
                            "How do I borrow equipment?",
                            "How do I edit my profile?",
                            "How do I upload a photo?",
                            "How do I use offline mode?",
                          ].map((question) {
                            return ActionChip(
                              label: Text(question),
                              onPressed: _answering
                                  ? null
                                  : () => _send(question),
                            );
                          }).toList(),
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(
                              hintText: "Ask how to use Stokli",
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: "Send",
                          onPressed: _answering ? null : () => _send(),
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({required this.isUser, required this.text});

  final bool isUser;
  final String text;
}
