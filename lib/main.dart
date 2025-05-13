import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const ChatScreen());
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isRecording = false;
  bool _isPlaying = false;
  late FlutterSoundRecorder _recorder;
  late FlutterSoundPlayer _player;
  String? _audioPath;
  late Database _database;
  int? _currentlyPlayingIndex;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    _initializeRecorder();
    _initializePlayer();
    _initDatabase();
    _loadSavedMessages();
  }

  Future<void> _initializePlayer() async {
    await _player.openPlayer();
  }

  Future<void> _initDatabase() async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'voice_messages.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE voice_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filePath TEXT,
            content TEXT,
            type TEXT,
            isMe INTEGER,
            createdAt TEXT
          )
        ''');
      },
    );
  }

  Future<void> _loadSavedMessages() async {
    final messages = await _database.query('voice_messages');
    setState(() {
      _messages.addAll(
        messages.map(
          (msg) => ChatMessage(
            type: msg['type'] == 'voice' ? MessageType.voice : MessageType.text,
            content: msg['content'] as String,
            isMe: msg['isMe'] == 1,
            timestamp: DateTime.parse(msg['createdAt'] as String),
          ),
        ),
      );
    });
  }

  Future<void> _initializeRecorder() async {
    await Permission.microphone.request();
    await _recorder.openRecorder();
  }

  Future<void> _startRecording() async {
    final tempDir = await getTemporaryDirectory();
    _audioPath =
        '${tempDir.path}/voice_message_${DateTime.now().millisecondsSinceEpoch}.aac';
    await _recorder.startRecorder(toFile: _audioPath!, codec: Codec.aacADTS);
    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();
    if (_audioPath != null) {
      _sendVoiceMessage();
    }
    setState(() {
      _isRecording = false;
    });
  }

  void _sendVoiceMessage() {
    final voiceMessage = ChatMessage(
      type: MessageType.voice,
      content: _audioPath!,
      isMe: true,
      timestamp: DateTime.now(),
    );
    setState(() {
      _messages.add(voiceMessage);
    });
    _saveMessageToDatabase(voiceMessage);
  }

  Future<void> _saveMessageToDatabase(ChatMessage message) async {
    await _database.insert('voice_messages', {
      'filePath': message.type == MessageType.voice ? message.content : null,
      'content': message.content,
      'type': message.type == MessageType.voice ? 'voice' : 'text',
      'isMe': message.isMe ? 1 : 0,
      'createdAt': message.timestamp.toIso8601String(),
    });
  }

  void _sendTextMessage() {
    final textMessage = ChatMessage(
      type: MessageType.text,
      content: _textController.text,
      isMe: true,
      timestamp: DateTime.now(),
    );
    setState(() {
      _messages.add(textMessage);
    });
    _textController.clear();
    _saveMessageToDatabase(textMessage);
  }

  Future<void> _playVoiceMessage(String path, int index) async {
    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() {
        _isPlaying = false;
        _currentlyPlayingIndex = null;
      });
      return;
    }

    await _player.startPlayer(
      fromURI: path,
      codec: Codec.aacADTS,
      whenFinished: () {
        setState(() {
          _isPlaying = false;
          _currentlyPlayingIndex = null;
        });
      },
    );
    setState(() {
      _isPlaying = true;
      _currentlyPlayingIndex = index;
    });
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _player.closePlayer();
    _database.close();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: _messages.length,
                itemBuilder: (ctx, index) {
                  final message = _messages[_messages.length - 1 - index];
                  return _buildMessage(message, _messages.length - 1 - index);
                },
              ),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_isRecording ? Icons.stop : Icons.mic),
            color: _isRecording ? Colors.red : Colors.blue,
            onPressed:
                () => _isRecording ? _stopRecording() : _startRecording(),
          ),
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(hintText: 'Type a message...'),
              onSubmitted: (text) {
                if (text.isNotEmpty) {
                  _sendTextMessage();
                }
              },
            ),
          ),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: () {
              if (_textController.text.isNotEmpty) {
                _sendTextMessage();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(ChatMessage message, int index) {
    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isMe ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.type == MessageType.text) Text(message.content),
            if (message.type == MessageType.voice)
              Row(
                children: [
                  Icon(Icons.audiotrack, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'Voice message',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                  SizedBox(width: 12),
                  IconButton(
                    icon: Icon(
                      _currentlyPlayingIndex == index && _isPlaying
                          ? Icons.stop
                          : Icons.play_arrow,
                    ),
                    onPressed: () => _playVoiceMessage(message.content, index),
                  ),
                ],
              ),
            Text(
              DateFormat('HH:mm').format(message.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

enum MessageType { text, voice }

class ChatMessage {
  final MessageType type;
  final String content;
  final bool isMe;
  final DateTime timestamp;

  ChatMessage({
    required this.type,
    required this.content,
    required this.isMe,
    required this.timestamp,
  });
}
