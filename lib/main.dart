import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_audio/tflite_audio.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Recorder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const RecorderPage(),
    );
  }
}

class RecorderPage extends StatefulWidget {
  const RecorderPage({Key? key}) : super(key: key);

  @override
  _RecorderPageState createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  FlutterSoundRecorder? _audioRecorder;
  FlutterSoundPlayer? _audioPlayer;
  bool isRecording = false;
  bool isPlaying = false;
  String statusText = '';
  late String _audioPath;
  List<String> recordings = [];
  Stream<Map<dynamic, dynamic>>? result;
  final String label = 'assets/audio_labels.txt';

  @override
  void initState() {
    super.initState();
    _audioRecorder = FlutterSoundRecorder();
    _audioPlayer = FlutterSoundPlayer();
    _audioPath = '';
    loadModel();
  }

  Future<void> loadModel() async {
    await TfliteAudio.loadModel(
      model: 'assets/audio_model.tflite',
      label: 'assets/audio_labels.txt',
      isAsset: true,
      inputType: 'file',
    );
  }

  void startRecognition() {
    result = TfliteAudio.startFileRecognition(
      audioDirectory: _audioPath,
      sampleRate: 16000,
      audioLength: 16000,
      detectionThreshold: 0.3,
      averageWindowDuration: 1000,
      minimumTimeBetweenSamples: 30,
      suppressionTime: 1500,
    );

    result?.listen((event) {
      log("Recognition Result: " + event["recognitionResult"].toString());
      setState(() {
        statusText = event["recognitionResult"].toString();
      });
    }).onDone(() {
      setState(() {
        result = null;
      });
    });
  }

  Future<List<String>> fetchLabelList() async {
    List<String> _labelList = [];
    await rootBundle.loadString(this.label).then((q) {
      for (String i in const LineSplitter().convert(q)) {
        _labelList.add(i);
      }
    });
    print('object');
    print(_labelList);
    return _labelList;
  }

  int i = 0;

  Future<void> startRecording() async {
    PermissionStatus micStatus = await Permission.microphone.request();
    if (micStatus != PermissionStatus.granted) {
      print('Microphone permission denied');
      return;
    }

    PermissionStatus storageStatus = await Permission.storage.request();
    if (storageStatus != PermissionStatus.granted) {
      print('Storage permission denied');
      return;
    }

    try {
      await _audioRecorder!.openRecorder();
      String tempDirPath = (await getTemporaryDirectory()).path;
      _audioPath = '$tempDirPath/recorded_audio${i}.wav';

      await _audioRecorder!.startRecorder(
        toFile: _audioPath,
        codec: Codec.pcm16WAV,
      );
      i++;
      setState(() {
        isRecording = true;
        statusText = 'Recording';
      });
    } catch (e) {
      print('Recording Error: $e');
    }
  }

  Future<void> stopRecording() async {
    try {
      await _audioRecorder!.stopRecorder();
      await _audioRecorder!.closeRecorder();
      setState(() {
        isRecording = false;
        statusText = 'Stopped';
        recordings.add(_audioPath);
      });
    } catch (e) {
      print('Stopping Error: $e');
    }
  }

  Future<void> playAudio(String audioPath) async {
    try {
      await _audioPlayer!.openPlayer();
      setState(() {
        isPlaying = true;
      });

      await _audioPlayer!.startPlayer(
        fromURI: audioPath,
      );

      startRecognition(); // Start audio recognition while playing

      setState(() {
        isPlaying = false;
      });
    } catch (e) {
      print('Audio Playback Error: $e');
    }
  }

  @override
  void dispose() {
    _audioRecorder?.closeRecorder();
    _audioPlayer?.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Recorder'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(statusText),
            SizedBox(height: 20),
            if (isRecording)
              ElevatedButton(
                onPressed: stopRecording,
                child: const Text('Stop Recording'),
              )
            else
              ElevatedButton(
                onPressed: startRecording,
                child: const Text('Start Recording'),
              ),
            SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: recordings.length,
                itemBuilder: (context, index) {
                  final recording = recordings[index];
                  return ListTile(
                    title: Text('Recording ${index + 1}'),
                    subtitle: Text(recording),
                    trailing: isPlaying
                        ? AnimatedIcon(
                      icon: AnimatedIcons.play_pause,
                      progress: _audioPlayer!.isPlaying
                          ? const AlwaysStoppedAnimation(0.0)
                          : const AlwaysStoppedAnimation(1.0),
                    )
                        : null,
                    onTap: () {
                      playAudio(recording);
                    },
                  );
                },
              ),
            ),
            FutureBuilder<List<String>>(
              future: fetchLabelList(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                } else if (snapshot.hasData) {
                  return labelListWidget(snapshot.data, statusText);
                } else {
                  return const Text('Failed to load label list.');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget labelListWidget(List<String>? labelList, String? result) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: labelList!.map((label) {
          if (label == result) {
            print(result);
            return Padding(
              padding: const EdgeInsets.all(5.0),
              child: Text(
                label.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 25,
                  color: Colors.green,
                ),
              ),
            );
          } else {
            print(result);
            return Padding(
              padding: const EdgeInsets.all(5.0),
              child: Text(
                label.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            );
          }
        }).toList(),
      ),
    );
  }
}
