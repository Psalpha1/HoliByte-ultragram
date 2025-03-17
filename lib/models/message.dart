class Message {
  Message({
    required this.toId,
    required this.msg,
    required this.read,
    required this.type,
    required this.fromId,
    required this.sent,
    this.localImgPath,
    this.replyTo,
    this.fileName, // Add fileName field
    this.fileSize, // Add fileSize field
    this.fileType, // Add fileType field
    this.sending = false, // Add sending field
    this.reactions = const [], // Add reactions field
    this.forwarded = false, // Add forwarded field
  });

  late final String toId;
  late final String msg;
  late final String read;
  late final String fromId;
  late final String sent;
  late final String? localImgPath;
  late final String? replyTo;
  late final Type type;
  late final String? fileName; // For file name
  late final int? fileSize; // For file size in bytes
  late final String? fileType; // For file MIME type
  late final bool sending; // Add sending field
  late final List<String> reactions; // Add reactions field
  late final bool forwarded; // Add forwarded field

  Message.fromJson(Map<String, dynamic> json) {
    toId = json['toId'].toString();
    msg = json['msg'].toString();
    read = json['read'].toString();
    type = _getMessageType(json['type'].toString());
    fromId = json['fromId'].toString();
    sent = json['sent'].toString();
    localImgPath = json['localImgPath']?.toString();
    replyTo = json['replyTo']?.toString();
    fileName = json['fileName']?.toString();
    fileSize = json['fileSize'] as int?;
    fileType = json['fileType']?.toString();
    sending = json['sending'] as bool? ?? false; // Add sending field
    reactions = (json['reactions'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        []; // Add reactions field
    forwarded = json['forwarded'] as bool? ?? false; // Add forwarded field
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['toId'] = toId;
    data['msg'] = msg;
    data['read'] = read;
    data['type'] = type.name;
    data['fromId'] = fromId;
    data['sent'] = sent;
    data['localImgPath'] = localImgPath;
    data['replyTo'] = replyTo;
    data['sending'] = sending;
    data['reactions'] = reactions;
    data['forwarded'] = forwarded;
    if (type == Type.file || type == Type.video) {
      data['fileName'] = fileName;
      data['fileSize'] = fileSize;
      data['fileType'] = fileType;
    }
    return data;
  }

  // Helper method to determine message type
  Type _getMessageType(String typeStr) {
    switch (typeStr) {
      case 'text':
        return Type.text;
      case 'image':
        return Type.image;
      case 'file':
        return Type.file;
      case 'audio':
        return Type.audio;
      case 'video':
        return Type.video;
      default:
        return Type.text;
    }
  }
}

enum Type { text, image, file, audio, video }

// ai message
class AiMessage {
  String msg;
  final MessageType msgType;

  AiMessage({required this.msg, required this.msgType});
}

enum MessageType { user, bot }
