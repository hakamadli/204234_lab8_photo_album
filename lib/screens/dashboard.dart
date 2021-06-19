import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as path;
import 'package:image_picker/image_picker.dart';

class Dashboard extends StatefulWidget {
  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  FirebaseStorage storage = FirebaseStorage.instance;
  CollectionReference imgRef;
  String _locationMessage = "";
  String _uploadTime = "";
  String _userDescription = "";
  final _descriptionController = TextEditingController();
  

  // Determine location on upload  
  void _getCurrentLocation() async {

    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    print(position);

    setState(() {
      _locationMessage = "${position.latitude}, ${position.longitude}";
      _uploadTime = "${position.timestamp}";
    });
  }
  
  // Select a photo from the gallery or camera to upload
  Future<void> _upload(String uploadType) async {
    final picker = ImagePicker();
    PickedFile pickedImage;
    try {
      pickedImage = await picker.getImage(
          source: uploadType == 'camera'
              ? ImageSource.camera
              : ImageSource.gallery,
              maxWidth: 1920);

      final String fileName = path.basename(pickedImage.path);
      File imageFile = File(pickedImage.path);

      _getCurrentLocation();
      

      try {     
        // Upload the selected photo with some custom meta data
        await storage.ref().child('Gallery/${fileName}').putFile(
            imageFile,
            SettableMetadata(customMetadata: {
              'description': 'New Image',
              'location': _locationMessage,
              'dateTime': _uploadTime,
            })).whenComplete(() async {
              await storage.ref().child('Gallery/${fileName}').getDownloadURL().then((value) {
                imgRef.add({'url': value, 'description': 'New Image', 'location': _locationMessage, 'dateTime': _uploadTime});
              },);
            });

        // Refresh the UI
        setState(() {});
      } on FirebaseException catch (error) {
        print(error);
      }
    } catch (e) {
      print(e);
    }
  }

  @override
  void initState() {
    super.initState();
    imgRef = FirebaseFirestore.instance.collection('Posts');
  }

  // Retrieve the uploaded images
  Future<List<Map<String, dynamic>>> _loadImages() async {
    List<Map<String, dynamic>> files = [];

    final ListResult result = await storage.ref().child('Gallery').listAll();
    final List<Reference> allFiles = result.items;

    await Future.forEach<Reference>(allFiles, (file) async {
      final String fileUrl = await file.getDownloadURL();
      final FullMetadata fileMeta = await file.getMetadata();
      files.add({
        "url": fileUrl,
        "path": file.fullPath,
        "description": fileMeta.customMetadata['description'],
        "location": _locationMessage ?? fileMeta.customMetadata['location'],
        "dateTime": _uploadTime ?? fileMeta.customMetadata['dateTime']
      });
    });
    return files;
  }

  // Delete the selected image
  Future<void> _delete(String ref) async {
    await storage.ref(ref).delete();
    // Rebuild the UI
    setState(() {});
  }

  // Edit description
  void _setDescription(String ref) async {
    await storage.ref(ref).updateMetadata(
      SettableMetadata(customMetadata: {
        'description': _userDescription
        })
      );
    // Rebuild the UI
    setState(() {});
  }

  // Edit description form
  Future<void> _showEditForm(String ref) {
    return showDialog(
      context: context, 
      barrierDismissible: true, 
      builder: (param) {
        return AlertDialog(
          actions: <Widget>[
            FlatButton(
              color: Colors.red,
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            FlatButton(
              color: Colors.green, 
              onPressed: () async {
                              
                setState(() {
                  _userDescription = _descriptionController.text;
                });

                _setDescription(ref);
                imgRef.doc(ref).update({'description': _descriptionController.text});

                if (_descriptionController.text.isNotEmpty) {
                  Navigator.pop(context);
                  _descriptionController.text = '';
                }
              },
              child: Text('Update'),
            ),
          ],
          title: Text('Edit description'),
          content: SingleChildScrollView(child: Column(
            children: <Widget>[
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  hintText: 'Enter a new description'
                ),
              ),
            ],
          ),
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Your photos'),
        backgroundColor: Colors.deepPurpleAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton.icon(
                    onPressed: () => _upload('camera'),
                    icon: Icon(Icons.camera),
                    label: Text('Camera')),
                ElevatedButton.icon(
                    onPressed: () => _upload('gallery'),
                    icon: Icon(Icons.library_add),
                    label: Text('Gallery')),
              ],
            ),
            Expanded(
              child: FutureBuilder(
                future: _loadImages(),
                builder: (context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    return ListView.builder(
                      itemCount: snapshot.data.length,
                      itemBuilder: (context, index) {
                        final image = snapshot.data[index];
                        return Card(
                          elevation: 5,
                          margin: EdgeInsets.symmetric(vertical: 5),
                          child: ListTile(
                            dense: false,
                            leading: Image.network(image['url']),
                            title: Text(image['description']),
                            subtitle: Column(
                              children: <Widget>[
                                Text('Location: ' + image['location']), 
                                Text('Date & Time: ' + image['dateTime']),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  onPressed: () => _showEditForm(image['path']),
                                  icon: Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _delete(image['path']),
                                  icon: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                ),
                              ]
                            )
                          ),
                        );
                      },
                    );
                  } 
                  return Center(
                    child: CircularProgressIndicator(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}