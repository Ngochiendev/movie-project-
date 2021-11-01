// Copyright (C) 2021 d1y <chenhonzhou@gmail.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cupertino_list_tile/cupertino_list_tile.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:movie/config.dart';
import 'package:movie/impl/movie.dart';
import 'package:movie/mirror/mirror.dart';
import 'package:movie/mirror/mirror_serialize.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

/// 历史记录处理类型
enum UpdateSearchHistoryType {
  /// 添加
  add,

  /// 删除
  remove,

  /// 清除所有
  clean
}

class HomeController extends GetxController {
  var currentBarIndex = 0;

  final localStorage = GetStorage();

  bool _isNsfw = false;

  bool get isNsfw {
    return _isNsfw;
  }

  set isNsfw(newVal) {
    _isNsfw = newVal;
    update();
    localStorage.write(ConstDart.is_nsfw, newVal);
  }

  List<String> _searchHistory = [];

  List<String> get searchHistory {
    return _searchHistory;
  }

  set searchHistory(List<String> newSearchHistory) {
    _searchHistory = newSearchHistory;
    update();
    localStorage.write(ConstDart.search_history, newSearchHistory);
  }

  /// 操作历史记录
  handleUpdateSearchHistory(
    String text, {
    type = UpdateSearchHistoryType.add,
  }) {
    switch (type) {
      case UpdateSearchHistoryType.add: // 添加
        _searchHistory.remove(text);
        _searchHistory.insert(0, text);
        searchHistory = _searchHistory;
        break;
      case UpdateSearchHistoryType.remove: // 删除单个
        _searchHistory.remove(text);
        searchHistory = _searchHistory;
        break;
      case UpdateSearchHistoryType.clean: // 清除所有
        searchHistory = [];
        break;
      default:
    }
    update();
  }

  int get mirrorIndex {
    return localStorage.read(ConstDart.ls_mirrorIndex) ?? 0;
  }

  set mirrorIndex(int newVal) {
    localStorage.write(ConstDart.ls_mirrorIndex, newVal);
  }

  set _mirrorIndex(int newVal) {
    mirrorIndex = newVal;
    update();
    updateHomeData(
      isFirst: true,
    );
  }

  MovieImpl get currentMirrorItem {
    return mirrorList[mirrorIndex];
  }

  List<MovieImpl> get mirrorList {
    if (isNsfw) return MirrorList;
    return MirrorList.where((e) => !e.isNsfw).toList();
  }

  int page = 1;
  int limit = 10;

  set _page(newVal) {
    // TODO
  }

  set _limit(newVal) {
    // TODO
  }

  List<MirrorOnceItemSerialize> homedata = [];

  bool isLoading = false;

  RefreshController refreshController = RefreshController(
    initialRefresh: false,
  );

  showMirrorModel(BuildContext context) {
    showCupertinoModalBottomSheet(
      context: context,
      builder: (context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: Container(),
          middle: Text('视频源'),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: mirrorList
                  .map(
                    (e) => CupertinoListTile(
                      onTap: () {
                        var index = MirrorList.indexOf(e);
                        _mirrorIndex = index;
                        Get.back();
                      },
                      title: Text(
                        e.meta.name,
                        style: TextStyle(
                          color: e.isNsfw
                              ? Colors.red
                              : (Get.isDarkMode ? Colors.white : Colors.black),
                        ),
                      ),
                      subtitle: Text(
                        e.meta.desc,
                        style: TextStyle(
                          color: Get.isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      leading: e.meta.logo.isEmpty
                          ? Image.asset(
                              "assets/images/fishtank.png",
                              width: 80,
                            )
                          : CachedNetworkImage(
                              width: 80,
                              imageUrl: e.meta.logo,
                              placeholder: (
                                context,
                                url,
                              ) =>
                                  Center(child: CircularProgressIndicator(),),
                              errorWidget: (
                                context,
                                url,
                                error,
                              ) =>
                                  Icon(Icons.error),
                            ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  void refreshOnLoading() async {
    page++;
    update();
    await updateHomeData();
    refreshController.loadComplete();
  }

  @override
  void onInit() {
    super.onInit();
    updateNsfwSetting();
    updateSearchHistory();
    updateHomeData(isFirst: true);
  }

  updateNsfwSetting() {
    _isNsfw = localStorage.read(ConstDart.is_nsfw) ?? false;
    update();
  }

  updateSearchHistory() {
    _searchHistory =
        List<String>.from(localStorage.read(ConstDart.search_history) ?? []);
    update();
  }

  Future<List<MirrorOnceItemSerialize>> updateSearchData(String keyword) async {
    var resp = await currentMirrorItem.getSearch(keyword: keyword);
    return resp;
  }

  /// [isFirst] 初始化加载数据需要将 [isLoading] => true
  updateHomeData({bool isFirst = false}) async {
    if (isFirst) {
      isLoading = true;
      page = 1;
      update();
    }
    print("handle axaj get page: $page, $limit");
    List<MirrorOnceItemSerialize> data = await currentMirrorItem.getHome(
      page: page,
      limit: limit,
    );
    if (isFirst) {
      homedata = data;
    } else {
      homedata.addAll(data);
    }
    isLoading = false;
    update();
  }

  @override
  void onReady() {
    refreshController = new RefreshController();
    super.onReady();
  }

  @override
  void onClose() {}
  void changeCurrentBarIndex(int i) {
    currentBarIndex = i;
    update();
  }
}
