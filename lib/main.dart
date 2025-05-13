import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const VoiceMessageScreen());
  }
}

class VoiceMessageScreen extends StatefulWidget {
  const VoiceMessageScreen({super.key});

  @override
  _VoiceMessageScreenState createState() => _VoiceMessageScreenState();
}

class _VoiceMessageScreenState extends State<VoiceMessageScreen> {
  late FlutterSoundRecorder _recorder;
  late FlutterSoundPlayer _player;
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _filePath;
  late Database _database;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    _initializeRecorder();
    _initializePlayer();
    _initDatabase();
  }

  // Initialize the Flutter Sound player.
  Future<void> _initializePlayer() async {
    await _player.openPlayer();
  }

  // Initialize the SQLite database and create the voice_messages table if it doesn't exist.
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
            createdAt TEXT
          )
        ''');
      },
    );
  }

  // Request microphone permission and open an audio session.
  Future<void> _initializeRecorder() async {
    await Permission.microphone.request();
    await _recorder.openRecorder();
  }

  // Start recording and save to a temporary file.
  Future<void> _startRecording() async {
    Directory tempDir = await getTemporaryDirectory();
    _filePath = '${tempDir.path}/voice_message.aac';
    await _recorder.startRecorder(toFile: _filePath, codec: Codec.aacADTS);
    setState(() {
      _isRecording = true;
    });
  }

  // Stop recording, update the UI, and store the voice message details.
  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();
    setState(() {
      _isRecording = false;
    });
    // Optionally, wait a moment to ensure the file is completely written.
    Future.delayed(Duration(milliseconds: 200), () => _sendVoiceMessage());
  }

  // Insert the voice message details into the SQLite database.
  Future<void> _sendVoiceMessage() async {
    if (_filePath == null) return;
    File audioFile = File(_filePath!);
    if (await audioFile.exists()) {
      print('File exists at: ${audioFile.path}');
      print('File size: ${await audioFile.length()} bytes');
    } else {
      print('Recorded file does not exist.');
    }
    await _saveVoiceMessageToDatabase(_filePath!);
  }

  Future<void> _saveVoiceMessageToDatabase(String filePath) async {
    await _database.insert('voice_messages', {
      'filePath': filePath,
      'createdAt': DateTime.now().toIso8601String(),
    });
    print('Voice message saved to local database.');
  }

  // Start playing the recorded audio.
  Future<void> _startPlayback() async {
    if (_filePath == null) return;
    await _player.startPlayer(
      fromURI: _filePath,
      codec: Codec.aacADTS,
      whenFinished: () {
        setState(() {
          _isPlaying = false;
        });
      },
    );
    setState(() {
      _isPlaying = true;
    });
  }

  // Stop the audio playback.
  Future<void> _stopPlayback() async {
    await _player.stopPlayer();
    setState(() {
      _isPlaying = false;
    });
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _player.closePlayer();
    _database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Message')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Button to start/stop recording.
            ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
            const SizedBox(height: 20),
            // Button to play/stop playback.
            ElevatedButton(
              // Enable only if a recording exists.
              onPressed:
                  _filePath == null
                      ? null
                      : _isPlaying
                      ? _stopPlayback
                      : _startPlayback,
              child: Text(_isPlaying ? 'Stop Playback' : 'Play Recording'),
            ),
          ],
        ),
      ),
    );
  }
}
