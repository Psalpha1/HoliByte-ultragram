import 'package:flutter/material.dart';
import '../api/apis.dart';
import '../helper/dialogs.dart';
import '../models/chat_user.dart';
import '../widgets/profile_image.dart';

class SelectContactsScreen extends StatefulWidget {
  final List<String> existingMembers;
  final String title;
  final bool allowMultiple;

  const SelectContactsScreen({
    super.key, 
    required this.existingMembers,
    this.title = 'Select Contacts',
    this.allowMultiple = true,
  });

  @override
  State<SelectContactsScreen> createState() => _SelectContactsScreenState();
}

class _SelectContactsScreenState extends State<SelectContactsScreen> {
  List<ChatUser> _contacts = [];
  List<ChatUser> _filteredContacts = [];
  final List<String> _selectedContactIds = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Load all contacts
  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);

    try {
      // Get all users
      final snapshot = await APIs.firestore.collection('users').get();
      
      // Convert to ChatUser objects
      final allUsers = snapshot.docs
          .map((doc) => ChatUser.fromJson(doc.data()))
          .toList();
      
      // Filter out current user and existing members
      _contacts = allUsers.where((user) {
        return user.id != APIs.user.uid && 
               !widget.existingMembers.contains(user.id);
      }).toList();
      
      // Sort by name
      _contacts.sort((a, b) => a.name.compareTo(b.name));
      
      // Initialize filtered contacts
      _filteredContacts = List.from(_contacts);
    } catch (e) {
      if (mounted) {
        Dialogs.showSnackbar(context, 'Failed to load contacts');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Handle search
  void _handleSearch(String query) {
    if (query.isEmpty) {
      setState(() => _filteredContacts = List.from(_contacts));
      return;
    }

    final lowercaseQuery = query.toLowerCase();
    setState(() {
      _filteredContacts = _contacts.where((contact) {
        return contact.name.toLowerCase().contains(lowercaseQuery) ||
               contact.email.toLowerCase().contains(lowercaseQuery);
      }).toList();
    });
  }

  // Toggle selection of a contact
  void _toggleSelection(ChatUser contact) {
    setState(() {
      if (_selectedContactIds.contains(contact.id)) {
        _selectedContactIds.remove(contact.id);
      } else {
        // If single selection mode, clear previous selections
        if (!widget.allowMultiple) {
          _selectedContactIds.clear();
        }
        _selectedContactIds.add(contact.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_selectedContactIds.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context, _selectedContactIds);
              },
              icon: const Icon(Icons.check),
              label: Text(
                widget.allowMultiple 
                    ? 'Add (${_selectedContactIds.length})' 
                    : 'Add',
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: _handleSearch,
            ),
          ),
          
          // Loading indicator or contacts list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredContacts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_off,
                              size: 60,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No contacts found matching "${_searchController.text}"'
                                  : 'No contacts available',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_searchController.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: TextButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    _handleSearch('');
                                  },
                                  child: const Text('Clear Search'),
                                ),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredContacts.length,
                        itemBuilder: (context, index) {
                          final contact = _filteredContacts[index];
                          final isSelected = _selectedContactIds.contains(contact.id);
                          
                          return ListTile(
                            leading: ProfileImage(
                              url: contact.image,
                              size: 45,
                            ),
                            title: Text(
                              contact.name,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(contact.about),
                            trailing: isSelected
                                ? Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).primaryColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  )
                                : Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                  ),
                            onTap: () => _toggleSelection(contact),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
} 