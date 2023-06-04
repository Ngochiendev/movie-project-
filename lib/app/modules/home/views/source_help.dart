import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:movie/app/modules/home/views/home_config.dart';
import 'package:movie/app/widget/k_error_stack.dart';
import 'package:movie/app/widget/window_appbar.dart';
import 'package:movie/config.dart';
import 'package:movie/mirror/m_utils/m.dart';
import 'package:movie/mirror/m_utils/source_utils.dart';
import 'package:movie/mirror/mirror.dart';
import 'package:movie/utils/helper.dart';
import 'package:movie/utils/http.dart';
import 'package:clipboard/clipboard.dart';
import 'package:movie/utils/json.dart';

class SourceItemJSONData {
  String? title;
  String? url;
  String? msg;
  bool? nsfw;

  SourceItemJSONData({
    this.title,
    this.url,
    this.msg,
    this.nsfw,
  });

  SourceItemJSONData.fromJson(Map<String, dynamic> json) {
    title = json['title'];
    url = json['url'];
    msg = json['msg'];
    nsfw = json['nsfw'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['title'] = this.title;
    data['url'] = this.url;
    data['msg'] = this.msg;
    data['nswf'] = this.nsfw;
    return data;
  }
}

class SourceHelpTable extends StatefulWidget {
  const SourceHelpTable({Key? key}) : super(key: key);

  @override
  _SourceHelpTableState createState() => _SourceHelpTableState();
}

class _SourceHelpTableState extends State<SourceHelpTable> {
  bool get showNSFW {
    return GetStorage().read(ConstDart.is_nsfw) ?? false;
  }

  loadMirrorListApi() async {
    setState(() {
      _isLoadingFromAJAX = true;
    });
    try {
      // if (kDebugMode) await Future.delayed(Duration(seconds: 2));
      var resp = await XHttp.dio.get(FetchMirrorAPI);
      List<SourceItemJSONData> data = List.from(resp.data)
          .map((e) => SourceItemJSONData.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!showNSFW) {
        data = data.where((element) {
          return !(element.nsfw ?? true);
        }).toList();
      }
      setState(() {
        mirrors = data;
        _isLoadingFromAJAX = false;
        _loadingErrorStack = "";
      });
    } catch (e) {
      print(e);
      setState(() {
        _isLoadingFromAJAX = false;
        _loadingErrorStack = e.toString();
      });
    }
  }

  bool _isLoadingFromAJAX = false;

  String _loadingErrorStack = "";

  List<SourceItemJSONData> mirrors = [];

  @override
  void initState() {
    super.initState();
    loadMirrorListApi();
  }

  String get playfulConfirmText {
    return "我知道了";
  }

  handleCopyText({
    SourceItemJSONData? item,
    bool canCopyAll = false,
  }) async {
    List<SourceItemJSONData> actions = mirrors;
    if (!canCopyAll && item != null) actions = [item];
    var ctx = Get.context;
    if (ctx == null) return;
    await Future.forEach(actions, (SourceItemJSONData element) {
      var msg = element.msg ?? "";
      Completer completer = Completer();
      if (msg.isEmpty) {
        completer.complete();
        return completer.future;
      }
      showEasyCupertinoDialog(
        context: ctx,
        content: Text(element.msg ?? ""),
        title: element.title,
        confirmText: playfulConfirmText,
        onDone: () {
          Get.back();
          completer.complete();
        },
      );
      return completer.future;
    });

    String result = actions[0].url ?? "";

    if (canCopyAll) {
      result = "";
      actions.forEach((element) {
        result += '${element.url}\n';
      });
    }
    if (result.isEmpty) return;
    await FlutterClipboard.copy(result);
    showEasyCupertinoDialog(content: '已复制到剪贴板!');
  }

  String get _wrapperAjaxStatusLable {
    if (!_isLoadingFromAJAX) return "啥也没有";
    return "加载网络资源中";
  }

  /// 判断加载失败
  bool get _canLoadFail {
    return _loadingErrorStack.isNotEmpty && !_isLoadingFromAJAX;
  }

  /// 导入文件
  handleImportFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'json',
        'txt',
      ],
    );

    if (result == null) {
      showEasyCupertinoDialog(
        content: "未选择文件 :(",
        confirmText: playfulConfirmText,
      );
      return;
    }
    List<File> files = result.paths.map((path) => File(path!)).toList();

    // ==========================
    var SOURCE_KEY = "source";
    var FILENAME_KEY = "filename";
    // ==========================

    var data = files
        .where((e) => !isBinaryAsFile(e))
        .toList()
        .map<Map<String, dynamic>>((item) {
          String filename = item.uri.pathSegments.last;
          return {
            SOURCE_KEY: item.readAsStringSync(),
            FILENAME_KEY: filename,
          };
        })
        .toList()
        .where((e) => verifyStringIsJSON(e[SOURCE_KEY] as String))
        .toList();
    if (data.isEmpty) {
      showEasyCupertinoDialog(
        content: "导入的文件格式错误 :(",
        confirmText: playfulConfirmText,
      );
      return;
    }
    var _collData = new Map<String, List<KBaseMirrorMovie>>();
    data.forEach((item) {
      String source = item[SOURCE_KEY] as String;
      String filename = item[FILENAME_KEY] as String;
      var easyParseData = SourceUtils.tryParseDynamic(source);
      if (easyParseData == null) return;
      List<KBaseMirrorMovie> result = [];
      if (easyParseData is KBaseMirrorMovie) {
        result = [easyParseData];
      } else if (easyParseData is List) {
        var append = easyParseData
            .where((element) {
              return element != null;
            })
            .toList()
            .map((ele) {
              return ele as KBaseMirrorMovie;
            });
        result.addAll(append);
      }
      _collData[filename] = result;
    });

    String easyMessage = "";
    List<KBaseMirrorMovie> stack = [];

    _collData.forEach((k, v) async {
      int len = v.length;
      if (v.isNotEmpty) {
        stack.addAll(v);
        easyMessage += "$k中有$len个源\n";
      }
    });
    if (stack.isEmpty) {
      showEasyCupertinoDialog(
        content: "未导入源, 可能是JSON文件格式不对? :(",
        confirmText: playfulConfirmText,
      );
      return;
    } else {
      var _easyData = SourceUtils.mergeMirror(
        stack,
        diff: true,
      );
      var _diff = _easyData[0] as int;
      if (_diff > 0) {
        var newListData = _easyData[1] as dynamic;
        await MirrorManage.mergeMirror(newListData);
      }
      var diffMsg = "本次共合并$_diff个源!";
      if (_diff <= 0) {
        diffMsg = "本次未合并!没有新的源!";
      }
      easyMessage += '\n' + diffMsg;
      showEasyCupertinoDialog(
        content: Column(
          children: [
            Icon(
              CupertinoIcons.hand_thumbsup,
              size: 51,
              color: CupertinoColors.systemBlue,
            ),
            SizedBox(
              height: 24,
            ),
            Text(easyMessage),
          ],
        ),
        confirmText: "好耶ヾ(✿ﾟ▽ﾟ)ノ",
      );
    }
  }

  Widget get _errorWidget {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            "// 需要科学上网",
            style: TextStyle(
              decoration: TextDecoration.lineThrough,
              decorationColor: CupertinoColors.systemPink,
              color: CupertinoColors.systemPink,
              fontSize: 18,
            ),
          ),
          KErrorStack(
            msg: _loadingErrorStack,
          ),
        ],
      ),
    );
  }

  Widget get _mirrorEmptyStateWidget {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Builder(builder: (context) {
            if (_isLoadingFromAJAX) {
              return CircularProgressIndicator();
            }
            return Icon(CupertinoIcons.zzz);
          }),
          SizedBox(
            height: 24,
          ),
          Text(
            _wrapperAjaxStatusLable,
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: TextStyle(color: Get.isDarkMode ? Colors.white : Colors.black),
      child: CupertinoPageScaffold(
        navigationBar: CupertinoEasyAppBar(
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoNavigationBarBackButton(),
                  Text(
                    "o(-`д´- ｡)",
                    style: Theme.of(context).textTheme.headline6,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      right: 12,
                    ),
                    child: CupertinoButton.filled(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.arrow_down_square_fill,
                            color: CupertinoColors.white,
                          ),
                          SizedBox(
                            width: 3,
                          ),
                          Text(
                            "导入文件",
                            style: Theme.of(
                              context,
                            ).textTheme.bodyText1!.copyWith(
                                  color: CupertinoColors.white,
                                  fontSize: 12,
                                ),
                          ),
                        ],
                      ),
                      onPressed: handleImportFiles,
                    ),
                  ),
                ],
              ),
              Divider()
            ],
          ),
        ),
        child: SafeArea(
          child: Container(
            child: Column(
              children: [
                Expanded(
                  child: CupertinoScrollbar(
                    child: Builder(
                      builder: (context) {
                        if (mirrors.isEmpty) {
                          if (_canLoadFail) {
                            return _errorWidget;
                          }
                          return _mirrorEmptyStateWidget;
                        }
                        return ListView(
                          children: mirrors.map((item) {
                            return CupertinoListTile(
                              title: Text(
                                item.title ?? "",
                                style: TextStyle(
                                  color: Get.isDarkMode
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                handleCopyText(item: item);
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ),
                Builder(
                  builder: (context) {
                    if (mirrors.isEmpty) {
                      if (_canLoadFail)
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: 24,
                          ),
                          child: CupertinoButton.filled(
                            padding: EdgeInsets.all(12),
                            child: Text("重新加载"),
                            onPressed: () {
                              loadMirrorListApi();
                            },
                          ),
                        );
                      return SizedBox.shrink();
                    }
                    return Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 12,
                      ),
                      child: CupertinoButton.filled(
                        borderRadius: BorderRadius.circular(24),
                        child: Text("一键复制到剪贴板"),
                        onPressed: () {
                          handleCopyText(canCopyAll: true);
                        },
                      ),
                    );
                  },
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

showEasyCupertinoDialog({
  String? title,
  dynamic content,
  VoidCallback? onDone,
  BuildContext? context,
  String? confirmText,
}) {
  Widget child = SizedBox.shrink();
  String outputTitle = title ?? "提示";
  String outputConfrimText = confirmText ?? "确定";
  if (content is Widget) {
    child = content;
  } else if (content is String) {
    child = Text(content);
  }
  var ctx = Get.context as BuildContext;
  if (context != null) ctx = context;
  showCupertinoDialog(
    builder: (BuildContext context) => easyShowModalWidget(
      content: child,
      title: outputTitle,
      onDone: onDone,
      confirmText: outputConfrimText,
    ),
    context: ctx,
  );
}

class easyShowModalWidget extends StatelessWidget {
  const easyShowModalWidget({
    Key? key,
    this.onDone,
    required this.content,
    this.title = "提示",
    this.confirmText = "确定",
    this.confirmTextColor = Colors.red,
  }) : super(key: key);

  final VoidCallback? onDone;
  final String title;
  final Widget content;
  final String confirmText;
  final Color confirmTextColor;

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Column(
        children: [
          Text(title),
        ],
      ),
      content: content,
      actions: <CupertinoDialogAction>[
        CupertinoDialogAction(
          child: Text(
            confirmText,
            style: TextStyle(
              color: confirmTextColor,
            ),
          ),
          onPressed: () {
            if (onDone != null) {
              onDone!();
            } else {
              Get.back();
            }
          },
        ),
      ],
    );
  }
}
