import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';


class DraftStorageService {
  static const String _userDraftsKey = 'user_drafts';
  static const String _trainDraftsKey = 'train_drafts';
  static const String _entityDraftsKey = 'entity_drafts';

  static const String _draftKey = 'coach_form_drafts';
  static const String _premisesDraftKey = 'premises_form_drafts';

  /// Per-user key for coach/premises drafts. Drafts saved before per-user
  /// scoping (global key) are adopted by the first user who opens them.
  static String _scopedKey(SharedPreferences prefs, String baseKey) {
    String uid = '';
    try {
      final raw = prefs.getString('currentUser');
      if (raw != null) uid = (jsonDecode(raw)['uid'] ?? '').toString();
    } catch (_) {}
    if (uid.isEmpty) return baseKey;
    final key = '${baseKey}_$uid';
    final legacy = prefs.getString(baseKey);
    if (legacy != null && !prefs.containsKey(key)) {
      prefs.setString(key, legacy);
      prefs.remove(baseKey);
    }
    return key;
  }

  static String _getUserDraftsKey(String userId) {
    return '${_userDraftsKey}_$userId';
  }

  static String _getTrainDraftsKey(String userId) {
    return '${_trainDraftsKey}_$userId';
  }

  static String _getEntityDraftsKey(String userId) {
    return '${_entityDraftsKey}_$userId';
  }


  static Future<bool> saveUserDraft({
    required String currentUserId,
    required Map<String, dynamic> draftData,
    String? draftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getUserDraftsKey(currentUserId);

      final existingDraftsJson = prefs.getString(key);
      List<Map<String, dynamic>> drafts = [];

      if (existingDraftsJson != null) {
        drafts = List<Map<String, dynamic>>.from(jsonDecode(existingDraftsJson));
      }

      final draftToSave = {
        ...draftData,
        'draftId': draftId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'savedAt': DateTime.now().toIso8601String(),
        'isDraft': true,
      };

      if (draftId != null) {
        final index = drafts.indexWhere((d) => d['draftId'] == draftId);
        if (index != -1) {
          drafts[index] = draftToSave;
        } else {
          drafts.add(draftToSave);
        }
      } else {
        drafts.add(draftToSave);
      }

      await prefs.setString(key, jsonEncode(drafts));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getUserDrafts(String currentUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getUserDraftsKey(currentUserId);
      final draftsJson = prefs.getString(key);

      if (draftsJson == null) return [];

      return List<Map<String, dynamic>>.from(jsonDecode(draftsJson));
    } catch (e) {
      return [];
    }
  }

  static Future<bool> deleteUserDraft({
    required String currentUserId,
    required String draftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getUserDraftsKey(currentUserId);
      final draftsJson = prefs.getString(key);

      if (draftsJson == null) return false;

      List<Map<String, dynamic>> drafts =
          List<Map<String, dynamic>>.from(jsonDecode(draftsJson));

      drafts.removeWhere((d) => d['draftId'] == draftId);

      await prefs.setString(key, jsonEncode(drafts));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getUserDraft({
    required String currentUserId,
    required String draftId,
  }) async {
    try {
      final drafts = await getUserDrafts(currentUserId);
      return drafts.firstWhere(
        (d) => d['draftId'] == draftId,
        orElse: () => <String, dynamic>{},
      );
    } catch (e) {
      return null;
    }
  }


  static Future<bool> saveTrainDraft({
    required String currentUserId,
    required Map<String, dynamic> draftData,
    String? draftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getTrainDraftsKey(currentUserId);


      final existingDraftsJson = prefs.getString(key);
      List<Map<String, dynamic>> drafts = [];

      if (existingDraftsJson != null) {
        drafts = List<Map<String, dynamic>>.from(jsonDecode(existingDraftsJson));
      }


      final draftToSave = {
        ...draftData,
        'draftId': draftId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'savedAt': DateTime.now().toIso8601String(),
        'isDraft': true,
      };


      if (draftId != null) {
        final index = drafts.indexWhere((d) => d['draftId'] == draftId);
        if (index != -1) {
          drafts[index] = draftToSave;
        } else {
          drafts.add(draftToSave);
        }
      } else {
        drafts.add(draftToSave);
      }

      await prefs.setString(key, jsonEncode(drafts));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getTrainDrafts(String currentUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getTrainDraftsKey(currentUserId);
      final draftsJson = prefs.getString(key);

      if (draftsJson == null) return [];

      return List<Map<String, dynamic>>.from(jsonDecode(draftsJson));
    } catch (e) {
      return [];
    }
  }

  static Future<bool> deleteTrainDraft({
    required String currentUserId,
    required String draftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getTrainDraftsKey(currentUserId);
      final draftsJson = prefs.getString(key);

      if (draftsJson == null) return false;

      List<Map<String, dynamic>> drafts =
          List<Map<String, dynamic>>.from(jsonDecode(draftsJson));

      drafts.removeWhere((d) => d['draftId'] == draftId);

      await prefs.setString(key, jsonEncode(drafts));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getTrainDraft({
    required String currentUserId,
    required String draftId,
  }) async {
    try {
      final drafts = await getTrainDrafts(currentUserId);
      return drafts.firstWhere(
        (d) => d['draftId'] == draftId,
        orElse: () => <String, dynamic>{},
      );
    } catch (e) {
      return null;
    }
  }

  // <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<ENTITY DRAFTS <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

  static Future<bool> saveEntityDraft({
    required String currentUserId,
    required Map<String, dynamic> draftData,
    String? draftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getEntityDraftsKey(currentUserId);

      final existingDraftsJson = prefs.getString(key);
      List<Map<String, dynamic>> drafts = [];

      if (existingDraftsJson != null) {
        drafts = List<Map<String, dynamic>>.from(jsonDecode(existingDraftsJson));
      }

      final draftToSave = {
        ...draftData,
        'draftId': draftId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'savedAt': DateTime.now().toIso8601String(),
        'isDraft': true,
      };

      if (draftId != null) {
        final index = drafts.indexWhere((d) => d['draftId'] == draftId);
        if (index != -1) {
          drafts[index] = draftToSave;
        } else {
          drafts.add(draftToSave);
        }
      } else {
        drafts.add(draftToSave);
      }

      await prefs.setString(key, jsonEncode(drafts));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getEntityDrafts(String currentUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getEntityDraftsKey(currentUserId);
      final draftsJson = prefs.getString(key);

      if (draftsJson == null) return [];

      return List<Map<String, dynamic>>.from(jsonDecode(draftsJson));
    } catch (e) {
      return [];
    }
  }

  static Future<bool> deleteEntityDraft({
    required String currentUserId,
    required String draftId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getEntityDraftsKey(currentUserId);
      final draftsJson = prefs.getString(key);

      if (draftsJson == null) return false;

      List<Map<String, dynamic>> drafts =
          List<Map<String, dynamic>>.from(jsonDecode(draftsJson));

      drafts.removeWhere((d) => d['draftId'] == draftId);

      await prefs.setString(key, jsonEncode(drafts));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getEntityDraft({
    required String currentUserId,
    required String draftId,
  }) async {
    try {
      final drafts = await getEntityDrafts(currentUserId);
      return drafts.firstWhere(
        (d) => d['draftId'] == draftId,
        orElse: () => <String, dynamic>{},
      );
    } catch (e) {
      return null;
    }
  }

  //<<<<<<<<<<<<<<<<<<<<<<<<<Draft forms>>>>>>>>>>>>>>>>>>>>>>>>>>>


  static Future<void> saveDraft(Map<String, dynamic> draftData, {String? existingDraftId}) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getAllDrafts();

    String draftId;
    if (existingDraftId != null && existingDraftId.isNotEmpty) {
      // Update existing draft
      draftId = existingDraftId;
      draftData['draftId'] = draftId;
      draftData['updatedAt'] = DateTime.now().toIso8601String();
      // Keep original savedAt if it exists
      if (drafts[draftId] != null && drafts[draftId]['savedAt'] != null) {
        draftData['savedAt'] = drafts[draftId]['savedAt'];
      } else {
        draftData['savedAt'] = DateTime.now().toIso8601String();
      }
    } else {
      // Create new draft
      draftId = 'draft_${DateTime.now().millisecondsSinceEpoch}';
      draftData['draftId'] = draftId;
      draftData['savedAt'] = DateTime.now().toIso8601String();
      draftData['updatedAt'] = DateTime.now().toIso8601String();
    }

    drafts[draftId] = draftData;
    await prefs.setString(_scopedKey(prefs, _draftKey), jsonEncode(drafts));
  }

  static Future<Map<String, dynamic>> getAllDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final draftsString = prefs.getString(_scopedKey(prefs, _draftKey));
    if (draftsString == null) return {};
    return Map<String, dynamic>.from(jsonDecode(draftsString));
  }

  static Future<List<Map<String, dynamic>>> getDraftsList() async {
    final drafts = await getAllDrafts();
    return drafts.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> deleteDraft(String draftId) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getAllDrafts();
    drafts.remove(draftId);
    await prefs.setString(_scopedKey(prefs, _draftKey), jsonEncode(drafts));
  }

  static Future<Map<String, dynamic>?> getDraft(String draftId) async {
    final drafts = await getAllDrafts();
    return drafts[draftId];
  }



  static Future<void> savePremisesDraft(Map<String, dynamic> draftData, {String? existingDraftId}) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getAllPremisesDrafts();

    String draftId;
    if (existingDraftId != null && existingDraftId.isNotEmpty) {
      draftId = existingDraftId;
      draftData['draftId'] = draftId;
      draftData['updatedAt'] = DateTime.now().toIso8601String();
      if (drafts[draftId] != null && drafts[draftId]['savedAt'] != null) {
        draftData['savedAt'] = drafts[draftId]['savedAt'];
      } else {
        draftData['savedAt'] = DateTime.now().toIso8601String();
      }
    } else {
      // Create new draft
      draftId = 'premises_draft_${DateTime.now().millisecondsSinceEpoch}';
      draftData['draftId'] = draftId;
      draftData['savedAt'] = DateTime.now().toIso8601String();
      draftData['updatedAt'] = DateTime.now().toIso8601String();
    }

    drafts[draftId] = draftData;
    await prefs.setString(_scopedKey(prefs, _premisesDraftKey), jsonEncode(drafts));
  }

  static Future<Map<String, dynamic>> getAllPremisesDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final draftsString = prefs.getString(_scopedKey(prefs, _premisesDraftKey));
    if (draftsString == null) return {};
    return Map<String, dynamic>.from(jsonDecode(draftsString));
  }

  static Future<List<Map<String, dynamic>>> getPremisesDraftsList() async {
    final drafts = await getAllPremisesDrafts();
    return drafts.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> deletePremisesDraft(String draftId) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getAllPremisesDrafts();
    drafts.remove(draftId);
    await prefs.setString(_scopedKey(prefs, _premisesDraftKey), jsonEncode(drafts));
  }

  static Future<Map<String, dynamic>?> getPremisesDraft(String draftId) async {
    final drafts = await getAllPremisesDrafts();
    return drafts[draftId];
  }








  // <<<<<<<<<<<<<<<<< CLEANUP >>>>>>>>>>>>>>>>>>>>>>>>>>>>

  static Future<bool> clearUserDrafts(String currentUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getUserDraftsKey(currentUserId));
      await prefs.remove(_getTrainDraftsKey(currentUserId));
      await prefs.remove(_getEntityDraftsKey(currentUserId));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> clearAllDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith(_userDraftsKey) ||
            key.startsWith(_trainDraftsKey) ||
            key.startsWith(_entityDraftsKey)) {
          await prefs.remove(key);
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }
}