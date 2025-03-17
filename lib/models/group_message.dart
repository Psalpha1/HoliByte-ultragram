import 'message.dart';

class GroupMessage extends Message {
  GroupMessage({
    required String groupId,
    required super.msg,
    required super.read,
    required super.type,
    required super.fromId,
    required super.sent,
    super.localImgPath,
    super.replyTo,
    super.fileName,
    super.fileSize,
    super.fileType,
    super.sending,
    super.reactions,
    super.forwarded,
    required this.senderName,
    required this.senderImage,
  }) : super(
          toId: groupId,
        );

  late String senderName;
  late String senderImage;

  // Additional constructor from JSON
  GroupMessage.fromJson(super.json)
      : senderName = json['sender_name'] ?? '',
        senderImage = json['sender_image'] ?? '',
        super.fromJson();

  @override
  Map<String, dynamic> toJson() {
    final data = super.toJson();
    data['sender_name'] = senderName;
    data['sender_image'] = senderImage;
    return data;
  }
} 