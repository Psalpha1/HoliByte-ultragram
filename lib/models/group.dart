class Group {
  Group({
    required this.id,
    required this.name,
    required this.description,
    required this.image,
    required this.createdAt,
    required this.createdBy,
    required this.members,
    required this.admins,
    required this.lastMessage,
    required this.lastMessageTime,
    this.isPublic = false,
  });

  late String id;
  late String name;
  late String description;
  late String image;
  late String createdAt;
  late String createdBy;
  late List<String> members;
  late List<String> admins;
  late String lastMessage;
  late String lastMessageTime;
  late bool isPublic;

  Group.fromJson(Map<String, dynamic> json) {
    id = json['id'] ?? '';
    name = json['name'] ?? '';
    description = json['description'] ?? '';
    image = json['image'] ?? '';
    createdAt = json['created_at'] ?? '';
    createdBy = json['created_by'] ?? '';
    members = List<String>.from(json['members'] ?? []);
    admins = List<String>.from(json['admins'] ?? []);
    lastMessage = json['last_message'] ?? '';
    lastMessageTime = json['last_message_time'] ?? '';
    isPublic = json['is_public'] ?? false;
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['name'] = name;
    data['description'] = description;
    data['image'] = image;
    data['created_at'] = createdAt;
    data['created_by'] = createdBy;
    data['members'] = members;
    data['admins'] = admins;
    data['last_message'] = lastMessage;
    data['last_message_time'] = lastMessageTime;
    data['is_public'] = isPublic;
    return data;
  }

  // Add copyWith method for easy updates
  Group copyWith({
    String? id,
    String? name,
    String? description,
    String? image,
    String? createdAt,
    String? createdBy,
    List<String>? members,
    List<String>? admins,
    String? lastMessage,
    String? lastMessageTime,
    bool? isPublic,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      image: image ?? this.image,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      members: members ?? this.members,
      admins: admins ?? this.admins,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      isPublic: isPublic ?? this.isPublic,
    );
  }
}
