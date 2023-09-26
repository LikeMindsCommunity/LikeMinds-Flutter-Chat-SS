import 'dart:math' as math;

import 'package:cupertino_will_pop_scope/cupertino_will_pop_scope.dart';
import 'package:custom_pop_up_menu/custom_pop_up_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:likeminds_chat_ss_fl/src/bloc/chatroom/chatroom_bloc.dart';
import 'package:likeminds_chat_ss_fl/src/bloc/chatroom_action/chatroom_action_bloc.dart';
import 'package:likeminds_chat_ss_fl/src/bloc/conversation/conversation_bloc.dart';
import 'package:likeminds_chat_ss_fl/src/bloc/conversation_action/conversation_action_bloc.dart';
import 'package:likeminds_chat_ss_fl/src/bloc/home/home_bloc.dart';
import 'package:likeminds_chat_ss_fl/src/navigation/router.dart';
import 'package:likeminds_chat_ss_fl/src/service/likeminds_service.dart';
import 'package:likeminds_chat_ss_fl/src/service/media_service.dart';
import 'package:likeminds_chat_ss_fl/src/service/preference_service.dart';
import 'package:likeminds_chat_ss_fl/src/service/service_locator.dart';
import 'package:likeminds_chat_ss_fl/src/utils/analytics/analytics.dart';
import 'package:likeminds_chat_ss_fl/src/utils/chatroom/conversation_utils.dart';
import 'package:likeminds_chat_ss_fl/src/utils/constants/asset_constants.dart';
import 'package:likeminds_chat_ss_fl/src/utils/constants/ui_constants.dart';
import 'package:likeminds_chat_ss_fl/src/utils/media/media_helper.dart';
import 'package:likeminds_chat_ss_fl/src/utils/media/media_utils.dart';
import 'package:likeminds_chat_ss_fl/src/utils/simple_bloc_observer.dart';
import 'package:likeminds_chat_ss_fl/src/utils/tagging/helpers/tagging_helper.dart';
import 'package:likeminds_chat_ss_fl/src/utils/ui_utils.dart';
import 'package:likeminds_chat_ss_fl/src/widgets/chat_bar.dart';
import 'package:likeminds_chat_ss_fl/src/widgets/chatroom_menu.dart';
import 'package:likeminds_chat_ss_fl/src/widgets/chatroom_skeleton.dart';
import 'package:likeminds_chat_ss_fl/src/widgets/media/document/document_preview_factory.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:likeminds_chat_fl/likeminds_chat_fl.dart';
import 'package:likeminds_chat_ui_fl/likeminds_chat_ui_fl.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    super.key,
    required this.chatroomId,
  });

  final int chatroomId;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  late ConversationBloc _conversationBloc;
  late ConversationActionBloc _convActionBloc;
  late ChatroomBloc _chatroomBloc;
  late ChatroomActionBloc _chatroomActionBloc;

  ChatRoom? chatroom;
  User? user;

  int currentTime = DateTime.now().millisecondsSinceEpoch;
  Map<String, List<Media>> conversationAttachmentsMeta =
      <String, List<Media>>{};
  Map<String, Conversation> conversationMeta = <String, Conversation>{};
  Map<String, List<Media>> mediaFiles = <String, List<Media>>{};
  Map<int, User?> userMeta = <int, User?>{};

  bool showScrollButton = false;
  int lastConversationId = 0;
  List<Conversation> selectedConversations = <Conversation>[];
  final CustomPopupMenuController _customMenuController =
      CustomPopupMenuController();

  ValueNotifier rebuildConversationList = ValueNotifier(false);
  ValueNotifier rebuildChatBar = ValueNotifier(false);
  ValueNotifier showConversationActions = ValueNotifier(false);
  ValueNotifier<bool> rebuildChatTopic = ValueNotifier(true);
  bool showChatTopic = true;
  Conversation? localTopic;

  ScrollController scrollController = ScrollController();
  PagingController<int, Conversation> pagedListController =
      PagingController<int, Conversation>(firstPageKey: 1);

  int _page = 1;
  ModalRoute? _route;

  @override
  void initState() {
    super.initState();
    Bloc.observer = SimpleBlocObserver();
    _addPaginationListener();
    scrollController.addListener(() {
      _showScrollToBottomButton();
      _handleChatTopic();
    });
    // chatActionBloc = BlocProvider.of<ChatActionBloc>(context);
    // conversationBloc = ConversationBloc();
    user = locator<LMPreferenceService>().getUser();
    _conversationBloc = BlocProvider.of<ConversationBloc>(context);
    _chatroomBloc = BlocProvider.of<ChatroomBloc>(context);
    _convActionBloc = BlocProvider.of<ConversationActionBloc>(context);
    _chatroomActionBloc = BlocProvider.of<ChatroomActionBloc>(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _chatroomActionBloc.add(
      MarkReadChatroomEvent(chatroomId: widget.chatroomId),
    );
    super.dispose();
  }

  // Future<bool> _willPopCallback() {
  //   _chatroomActionBloc.add(
  //     MarkReadChatroomEvent(chatroomId: widget.chatroomId),
  //   );
  //   BlocProvider.of<HomeBloc>(context).add(UpdateHomeEvent());
  //   return Future.value(false);
  // }

  _addPaginationListener() {
    pagedListController.addPageRequestListener(
      (pageKey) {
        _conversationBloc.add(
          LoadConversations(
            getConversationRequest: (GetConversationRequestBuilder()
                  ..chatroomId(widget.chatroomId)
                  ..page(pageKey)
                  ..pageSize(500)
                  ..minTimestamp(0)
                  ..maxTimestamp(currentTime))
                .build(),
          ),
        );
      },
    );
  }

  void _handleChatTopic() {
    if (scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      if (!showChatTopic) {
        rebuildChatTopic.value = !rebuildChatTopic.value;
        showChatTopic = true;
      }
    } else {
      if (showChatTopic) {
        rebuildChatTopic.value = !rebuildChatTopic.value;
        showChatTopic = false;
      }
    }
  }

  Future<void> _scrollToBottom() async {
    await scrollController.animateTo(
      scrollController.position.minScrollExtent,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
    );
    if(!showChatTopic) {
      showChatTopic = true;
      rebuildChatTopic.value = ! rebuildChatTopic.value;
    }
  }

  void _showScrollToBottomButton() {
    if (scrollController.position.pixels >
        scrollController.position.viewportDimension) {
      _showButton();
    }
    if (scrollController.position.pixels <
        scrollController.position.viewportDimension) {
      _hideButton();
    }
  }

  void _showButton() {
    setState(() {
      showScrollButton = true;
    });
  }

  void _hideButton() {
    setState(() {
      showScrollButton = false;
    });
  }

  void updatePagingControllers(ConversationState state) {
    if (state is ConversationLoaded) {
      _page++;

      if (state.getConversationResponse.conversationMeta != null &&
          state.getConversationResponse.conversationMeta!.isNotEmpty) {
        conversationMeta
            .addAll(state.getConversationResponse.conversationMeta!);
      }

      if (state.getConversationResponse.conversationAttachmentsMeta != null &&
          state.getConversationResponse.conversationAttachmentsMeta!
              .isNotEmpty) {
        Map<String, List<Media>> getConversationAttachmentData = state
            .getConversationResponse.conversationAttachmentsMeta!
            .map((key, value) {
          return MapEntry(
            key,
            (value as List<dynamic>?)?.map((e) => Media.fromJson(e)).toList() ??
                [],
          );
        });
        conversationAttachmentsMeta.addAll(getConversationAttachmentData);
      }

      if (state.getConversationResponse.userMeta != null) {
        userMeta.addAll(state.getConversationResponse.userMeta!);
      }
      List<Conversation>? conversationData =
          state.getConversationResponse.conversationData;
      filterOutStateMessage(conversationData!);
      conversationData = addTimeStampInConversationList(
          conversationData, chatroom!.communityId!);
      if (state.getConversationResponse.conversationData == null ||
          state.getConversationResponse.conversationData!.isEmpty ||
          state.getConversationResponse.conversationData!.length < 500) {
        pagedListController.appendLastPage(conversationData ?? []);
      } else {
        pagedListController.appendPage(conversationData!, _page);
      }
    }
    if (state is ConversationPosted) {
      addConversationToPagedList(
        state.postConversationResponse.conversation!,
      );
    } else if (state is LocalConversation) {
      addLocalConversationToPagedList(state.conversation);
    } else if (state is MultiMediaConversationLoading) {
      if (!userMeta.containsKey(user!.id)) {
        userMeta[user!.id] = user;
      }
      mediaFiles[state.postConversation.temporaryId!] = state.mediaFiles;

      List<Conversation> conversationList =
          pagedListController.itemList ?? <Conversation>[];

      conversationList.insert(0, state.postConversation);

      rebuildConversationList.value = !rebuildConversationList.value;
    } else if (state is MultiMediaConversationPosted) {
      addMultiMediaConversation(
        state,
      );
    } else if (state is ConversationError) {
      toast(state.message);
    }
    if (state is ConversationUpdated) {
      if (state.response.id != lastConversationId) {
        addConversationToPagedList(
          state.response,
        );
        lastConversationId = state.response.id;
      }
    }
  }

  void addLocalConversationToPagedList(Conversation conversation) {
    List<Conversation> conversationList =
        pagedListController.itemList ?? <Conversation>[];

    if (conversation.replyId != null &&
        !conversationMeta.containsKey(conversation.replyId.toString())) {
      Conversation? replyConversation = pagedListController.itemList
          ?.firstWhere((element) =>
              element.id ==
              (conversation.replyId ?? conversation.replyConversation));
      if (replyConversation != null) {
        conversationMeta[conversation.replyId.toString()] = replyConversation;
      }
    }
    conversationList.insert(0, conversation);
    if (conversationList.length >= 500) {
      conversationList.removeLast();
    }
    if (!userMeta.containsKey(user!.id)) {
      userMeta[user!.id] = user;
    }

    pagedListController.itemList = conversationList;
    rebuildConversationList.value = !rebuildConversationList.value;
  }

  void updateEditedConversation(Conversation editedConversation) {
    List<Conversation> conversationList =
        pagedListController.itemList ?? <Conversation>[];
    int index = conversationList
        .indexWhere((element) => element.id == editedConversation.id);
    if (index != -1) {
      conversationList[index] = editedConversation;
    }

    if (conversationMeta.isNotEmpty &&
        conversationMeta.containsKey(editedConversation.id.toString())) {
      conversationMeta[editedConversation.id.toString()] = editedConversation;
    }
    pagedListController.itemList = conversationList;
    rebuildConversationList.value = !rebuildConversationList.value;
  }

  void addConversationToPagedList(Conversation conversation) {
    List<Conversation> conversationList =
        pagedListController.itemList ?? <Conversation>[];

    int index = conversationList.indexWhere(
        (element) => element.temporaryId == conversation.temporaryId);
    if (conversation.replyId != null &&
        !conversationMeta.containsKey(conversation.replyId.toString())) {
      Conversation? replyConversation = pagedListController.itemList
          ?.firstWhere((element) =>
              element.id ==
              (conversation.replyId ?? conversation.replyConversation));
      if (replyConversation != null) {
        conversationMeta[conversation.replyId.toString()] = replyConversation;
      }
    }
    if (index != -1) {
      conversationList[index] = conversation;
    } else if (conversationList.isNotEmpty) {
      if (conversationList.first.date != conversation.date) {
        conversationList.insert(
          0,
          Conversation(
            isTimeStamp: true,
            id: 1,
            hasFiles: false,
            attachmentCount: 0,
            attachmentsUploaded: false,
            createdEpoch: conversation.createdEpoch,
            chatroomId: chatroom!.id,
            date: conversation.date,
            memberId: conversation.memberId,
            userId: conversation.userId,
            temporaryId: conversation.temporaryId,
            answer: conversation.date ?? '',
            communityId: chatroom!.communityId!,
            createdAt: conversation.createdAt,
            header: conversation.header,
          ),
        );
      }
      conversationList.insert(0, conversation);
      if (conversationList.length >= 500) {
        conversationList.removeLast();
      }
      if (!userMeta.containsKey(user!.id)) {
        userMeta[user!.id] = user;
      }
    }
    pagedListController.itemList = conversationList;
    rebuildConversationList.value = !rebuildConversationList.value;
  }

  void addMultiMediaConversation(MultiMediaConversationPosted state) {
    if (!userMeta.containsKey(user!.id)) {
      userMeta[user!.id] = user;
    }
    if (!conversationAttachmentsMeta
        .containsKey(state.postConversationResponse.conversation!.id)) {
      List<Media> putMediaAttachment = state.putMediaResponse;
      conversationAttachmentsMeta[
              '${state.postConversationResponse.conversation!.id}'] =
          putMediaAttachment;
    }
    List<Conversation> conversationList =
        pagedListController.itemList ?? <Conversation>[];

    conversationList.removeWhere((element) =>
        element.temporaryId ==
        state.postConversationResponse.conversation!.temporaryId);

    mediaFiles.remove(state.postConversationResponse.conversation!.temporaryId);

    conversationList.insert(
      0,
      Conversation(
        id: state.postConversationResponse.conversation!.id,
        hasFiles: true,
        attachmentCount: state.putMediaResponse.length,
        attachmentsUploaded: true,
        chatroomId: chatroom!.id,
        state: state.postConversationResponse.conversation!.state,
        date: state.postConversationResponse.conversation!.date,
        memberId: state.postConversationResponse.conversation!.memberId,
        userId: state.postConversationResponse.conversation!.userId,
        temporaryId: state.postConversationResponse.conversation!.temporaryId,
        answer: state.postConversationResponse.conversation!.answer,
        communityId: chatroom!.communityId!,
        createdAt: state.postConversationResponse.conversation!.createdAt,
        header: state.postConversationResponse.conversation!.header,
        ogTags: state.postConversationResponse.conversation!.ogTags,
      ),
    );

    if (conversationList.length >= 500) {
      conversationList.removeLast();
    }
    rebuildConversationList.value = !rebuildConversationList.value;
  }

  void updateDeletedConversation(DeleteConversationResponse response) {
    List<Conversation> conversationList =
        pagedListController.itemList ?? <Conversation>[];
    int index = conversationList.indexWhere(
        (element) => element.id == response.conversations!.first.id);
    if (index != -1) {
      conversationList[index].deletedByUserId = user!.id;
    }
    if (conversationMeta.isNotEmpty &&
        conversationMeta
            .containsKey(response.conversations!.first.id.toString())) {
      conversationMeta[response.conversations!.first.id.toString()]!
          .deletedByUserId = user!.id;
    }
    pagedListController.itemList = conversationList;
    scrollController.animateTo(
      scrollController.position.pixels + 10,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
    );
    rebuildConversationList.value = !rebuildConversationList.value;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        floatingActionButton: showScrollButton
            ? Padding(
                padding: EdgeInsets.only(bottom: 18.h),
                child: Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: secondary.shade200,
                    boxShadow: [
                      BoxShadow(
                        offset: const Offset(0, 2),
                        blurRadius: 8,
                        color: kBlackColor.withOpacity(0.2),
                      )
                    ],
                  ),
                  child: Center(
                    child: LMIconButton(
                      containerSize: 42,
                      onTap: (active) {
                        _scrollToBottom();
                      },
                      icon: const LMIcon(
                        type: LMIconType.icon,
                        icon: Icons.keyboard_arrow_down,
                        color: Colors.white,
                        size: 24,
                        boxPadding: 6,
                        boxSize: 36,
                      ),
                    ),
                  ),
                ),
              )
            : null,
        body: SafeArea(
          bottom: false,
          left: false,
          right: false,
          child: BlocConsumer<ChatroomBloc, ChatroomState>(
            listener: (context, state) {
              if (state is ChatroomLoaded) {
                chatroom = state.getChatroomResponse.chatroom!;
                lastConversationId =
                    state.getChatroomResponse.lastConversationId ?? 0;
                _chatroomActionBloc
                    .add(MarkReadChatroomEvent(chatroomId: chatroom!.id));
                _conversationBloc.add(InitConversations(
                  chatroomId: chatroom!.id,
                  conversationId: lastConversationId,
                ));
                LMAnalytics.get().track(AnalyticsKeys.chatroomOpened, {
                  'chatroom_id': chatroom!.id,
                  'community_id': chatroom!.communityId,
                  'chatroom_type': chatroom!.type,
                  'source': 'home_feed',
                });
              }
            },
            builder: (context, state) {
              // return const SkeletonChatList();
              if (state is ChatroomLoading) {
                return const SkeletonChatPage();
              }

              if (state is ChatroomLoaded) {
                var pagedListView = ValueListenableBuilder(
                  valueListenable: rebuildConversationList,
                  builder: (context, _, __) {
                    return BlocConsumer<ConversationBloc, ConversationState>(
                        bloc: _conversationBloc,
                        listener: (context, state) =>
                            updatePagingControllers(state),
                        builder: (context, state) {
                          return PagedListView(
                            pagingController: pagedListController,
                            scrollController: scrollController,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            reverse: true,
                            scrollDirection: Axis.vertical,
                            builderDelegate:
                                PagedChildBuilderDelegate<Conversation>(
                              noItemsFoundIndicatorBuilder: (context) =>
                                  const SizedBox(height: 10),
                              firstPageProgressIndicatorBuilder: (context) =>
                                  const SkeletonChatList(),
                              newPageProgressIndicatorBuilder: (context) =>
                                  Padding(
                                padding: EdgeInsets.symmetric(vertical: 1.h),
                                child: const Column(
                                  children: [
                                    SkeletonChatBubble(isSent: true),
                                    SkeletonChatBubble(isSent: false),
                                    SkeletonChatBubble(isSent: true),
                                  ],
                                ),
                              ),
                              animateTransitions: true,
                              transitionDuration:
                                  const Duration(milliseconds: 500),
                              itemBuilder: (context, item, index) {
                                if (item.isTimeStamp != null &&
                                        item.isTimeStamp! ||
                                    item.state != 0 && item.state != null) {
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: item.isTimeStamp == null ||
                                                !item.isTimeStamp!
                                            ? 80.w
                                            : 35.w,
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 5,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: kWhiteColor.withOpacity(0.5),
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                            color: const Color.fromRGBO(
                                                226, 232, 240, 1),
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: LMTextView(
                                          text:
                                              TaggingHelper.extractStateMessage(
                                                  item.answer),
                                          textAlign: TextAlign.center,
                                          textStyle: const TextStyle(
                                            fontSize: 10,
                                            color: Color.fromRGBO(
                                                100, 116, 139, 1),
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )
                                    ],
                                  );
                                }

                                final replyAttachments = item.replyId != null
                                    ? conversationAttachmentsMeta.containsKey(
                                            item.replyId.toString())
                                        ? conversationAttachmentsMeta[
                                            item.replyId.toString()]
                                        : null
                                    : null;

                                Conversation? replyConversation =
                                    conversationMeta[item.replyId.toString()];

                                CustomPopupMenuController chatBubbleController =
                                    CustomPopupMenuController();

                                return item.userId == user!.id
                                    ? LMChatBubble(
                                        currentUser: user!,
                                        key: Key(item.id.toString()),
                                        menuController: chatBubbleController,
                                        isSent: item.userId == user!.id,
                                        backgroundColor: secondary.shade500,
                                        deletedText: item.deletedByUserId !=
                                                null
                                            ? getDeletedTextWidget(item, user!)
                                            : null,
                                        menu: ClipRRect(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            constraints: BoxConstraints(
                                              minWidth: 42.w,
                                              maxWidth: 60.w,
                                            ),
                                            // color: Colors.white,
                                            child: IntrinsicWidth(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  if (user!.id ==
                                                          chatroom!
                                                              .member!.id ||
                                                      user!.state == 1)
                                                    ListTile(
                                                      onTap: () {
                                                        chatBubbleController
                                                            .hideMenu();
                                                        if ((localTopic !=
                                                                    null &&
                                                                localTopic!
                                                                        .id ==
                                                                    item.id) ||
                                                            (chatroom!.topic !=
                                                                    null &&
                                                                item.id ==
                                                                    chatroom!
                                                                        .topic!
                                                                        .id)) {
                                                          toast(
                                                              "Message already pinned!");
                                                        } else {
                                                          _chatroomActionBloc
                                                              .add(
                                                            SetChatroomTopicEvent(
                                                              chatroomId:
                                                                  chatroom!.id,
                                                              conversationId:
                                                                  item.id,
                                                              topic: item,
                                                            ),
                                                          );
                                                        }
                                                      },
                                                      leading: const LMIcon(
                                                        type: LMIconType.svg,
                                                        assetPath: ssPinIcon,
                                                      ),
                                                      title: const LMTextView(
                                                        text: "Pin Message",
                                                        textStyle: TextStyle(
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                  ListTile(
                                                    onTap: () {
                                                      chatBubbleController
                                                          .hideMenu();
                                                      int userId =
                                                          item.userId ??
                                                              item.memberId!;
                                                      if (userId == user!.id) {
                                                        item.member = user!;
                                                      }
                                                      if (item.deletedByUserId !=
                                                          null) {
                                                        return;
                                                      }
                                                      _convActionBloc.add(
                                                        ReplyConversation(
                                                          chatroomId:
                                                              chatroom!.id,
                                                          conversationId:
                                                              item.id,
                                                          replyConversation:
                                                              item,
                                                        ),
                                                      );
                                                    },
                                                    leading: const LMIcon(
                                                      type: LMIconType.svg,
                                                      assetPath: ssReplyIcon,
                                                      size: 24,
                                                    ),
                                                    title: const LMTextView(
                                                      text: "Reply",
                                                      textStyle: TextStyle(
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                  ListTile(
                                                    onTap: () {
                                                      chatBubbleController
                                                          .hideMenu();
                                                      Clipboard.setData(
                                                        ClipboardData(
                                                          text: TaggingHelper
                                                                  .convertRouteToTag(
                                                                      item.answer) ??
                                                              '',
                                                        ),
                                                      ).then((value) {
                                                        toast(
                                                            "Copied to clipboard");
                                                      });
                                                    },
                                                    leading: const LMIcon(
                                                      type: LMIconType.svg,
                                                      assetPath: ssCopyIcon,
                                                      size: 24,
                                                    ),
                                                    title: const LMTextView(
                                                      text: "Copy",
                                                      textStyle: TextStyle(
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                  Visibility(
                                                    visible:
                                                        checkDeletePermissions(
                                                            item),
                                                    child: ListTile(
                                                      onTap: () async {
                                                        chatBubbleController
                                                            .hideMenu();
                                                        if ((localTopic !=
                                                                    null &&
                                                                localTopic!
                                                                        .id ==
                                                                    item.id) ||
                                                            (chatroom!.topic !=
                                                                    null &&
                                                                item.id ==
                                                                    chatroom!
                                                                        .topic!
                                                                        .id)) {
                                                          showDialog(
                                                            context: context,
                                                            builder:
                                                                (context) =>
                                                                    AlertDialog(
                                                              title: const Text(
                                                                  "Delete Message?"),
                                                              content: const Text(
                                                                  "Are you sure you want to delete this message? The message has been set as current topic of this chatroom"),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed:
                                                                      () {
                                                                    Navigator.pop(
                                                                        context);
                                                                  },
                                                                  child: const LMTextView(
                                                                      text:
                                                                          "CANCEL"),
                                                                ),
                                                                TextButton(
                                                                  onPressed:
                                                                      () {
                                                                    DeleteConversationRequest
                                                                        request =
                                                                        (DeleteConversationRequestBuilder()
                                                                              ..conversationIds([
                                                                                item.id
                                                                              ])
                                                                              ..reason("Delete"))
                                                                            .build();
                                                                    _convActionBloc.add(
                                                                        DeleteConversation(
                                                                            request));
                                                                  },
                                                                  child: const LMTextView(
                                                                      text:
                                                                          "DELETE"),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                        } else {
                                                          DeleteConversationRequest
                                                              request =
                                                              (DeleteConversationRequestBuilder()
                                                                    ..conversationIds([
                                                                      item.id
                                                                    ])
                                                                    ..reason(
                                                                        "Delete"))
                                                                  .build();
                                                          _convActionBloc.add(
                                                              DeleteConversation(
                                                                  request));
                                                        }
                                                      },
                                                      leading: const LMIcon(
                                                        type: LMIconType.svg,
                                                        assetPath: ssDeleteIcon,
                                                        color: Colors.red,
                                                        size: 24,
                                                      ),
                                                      title: const LMTextView(
                                                        text: "Delete",
                                                        textStyle: TextStyle(
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        onReply: (replyingTo) {
                                          int userId =
                                              item.userId ?? item.memberId!;
                                          if (userId == user!.id) {
                                            item.member = user!;
                                          }
                                          if (item.deletedByUserId != null) {
                                            return;
                                          }
                                          _convActionBloc.add(
                                            ReplyConversation(
                                              chatroomId: chatroom!.id,
                                              conversationId: item.id,
                                              replyConversation: replyingTo,
                                            ),
                                          );
                                        },
                                        outsideFooter: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Visibility(
                                              visible: item.isEdited != null &&
                                                  item.isEdited!,
                                              child: const LMTextView(
                                                text: "Edited • ",
                                                textStyle: TextStyle(
                                                  fontSize: 10,
                                                  color: Color.fromRGBO(
                                                      71, 85, 105, 1),
                                                ),
                                              ),
                                            ),
                                            LMTextView(
                                              text: item.createdAt,
                                              textStyle: const TextStyle(
                                                fontSize: 10,
                                                color: Color.fromRGBO(
                                                    71, 85, 105, 1),
                                              ),
                                            ),
                                          ],
                                        ),
                                        content: LMChatContent(
                                          conversation: item,
                                          textStyle: TextStyle(
                                            fontSize: 14,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary,
                                          ),
                                          tagStyle: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: primary.shade800,
                                          ),
                                          linkStyle: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: secondary.shade100,
                                          ),
                                          visibleLines: 2,
                                          animation: true,
                                        ),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(16),
                                          topRight: Radius.circular(16),
                                          bottomRight: Radius.zero,
                                          bottomLeft: Radius.circular(16),
                                        ),
                                        conversation: item,
                                        replyingTo: replyConversation,
                                        replyItem: LMReplyItem(
                                          replyToConversation:
                                              replyConversation,
                                          borderRadius: 10,
                                          title: replyConversation != null
                                              ? LMTextView(
                                                  text: userMeta[
                                                          replyConversation
                                                                  .userId ??
                                                              replyConversation
                                                                  .memberId!]!
                                                      .name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                  textStyle: const TextStyle(
                                                    color: kPrimaryColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                )
                                              : null,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                              .withOpacity(0.7),
                                          subtitle: replyConversation != null
                                              ? replyConversation
                                                          .deletedByUserId !=
                                                      null
                                                  ? getDeletedTextWidget(
                                                      replyConversation, user!)
                                                  : getChatItemAttachmentTile(
                                                      replyAttachments ?? [],
                                                      replyConversation,
                                                    )
                                              : null,
                                        ),
                                        sender: userMeta[
                                                item.userId ?? item.memberId] ??
                                            item.member!,
                                        mediaWidget:
                                            item.deletedByUserId == null
                                                ? getContent(item)
                                                : const SizedBox.shrink(),
                                      )
                                    : LMChatBubble(
                                        currentUser: user!,
                                        deletedText: item.deletedByUserId !=
                                                null
                                            ? getDeletedTextWidget(item, user!)
                                            : null,
                                        key: Key(item.id.toString()),
                                        isSent: item.userId == user!.id,
                                        menuController: chatBubbleController,
                                        backgroundColor: secondary.shade100,
                                        menu: ClipRRect(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            constraints: BoxConstraints(
                                              minWidth: 42.w,
                                              maxWidth: 60.w,
                                            ),
                                            // color: Colors.white,
                                            child: IntrinsicWidth(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  if (user!.id ==
                                                          chatroom!
                                                              .member!.id ||
                                                      user!.state == 1)
                                                    ListTile(
                                                      onTap: () {
                                                        chatBubbleController
                                                            .hideMenu();
                                                        if ((localTopic !=
                                                                    null &&
                                                                localTopic!
                                                                        .id ==
                                                                    item.id) ||
                                                            (chatroom!.topic !=
                                                                    null &&
                                                                item.id ==
                                                                    chatroom!
                                                                        .topic!
                                                                        .id)) {
                                                          toast(
                                                              "Message already pinned!");
                                                        } else {
                                                          _chatroomActionBloc
                                                              .add(
                                                            SetChatroomTopicEvent(
                                                              chatroomId:
                                                                  chatroom!.id,
                                                              conversationId:
                                                                  item.id,
                                                              topic: item,
                                                            ),
                                                          );
                                                        }
                                                      },
                                                      leading: const LMIcon(
                                                        type: LMIconType.svg,
                                                        assetPath: ssPinIcon,
                                                      ),
                                                      title: const LMTextView(
                                                        text: "Pin Message",
                                                        textStyle: TextStyle(
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                  ListTile(
                                                    onTap: () {
                                                      chatBubbleController
                                                          .hideMenu();
                                                      int userId =
                                                          item.userId ??
                                                              item.memberId!;
                                                      if (userId == user!.id) {
                                                        item.member = user!;
                                                      }
                                                      if (item.deletedByUserId !=
                                                          null) {
                                                        return;
                                                      }
                                                      _convActionBloc.add(
                                                        ReplyConversation(
                                                          chatroomId:
                                                              chatroom!.id,
                                                          conversationId:
                                                              item.id,
                                                          replyConversation:
                                                              item,
                                                        ),
                                                      );
                                                    },
                                                    leading: const LMIcon(
                                                      type: LMIconType.svg,
                                                      assetPath: ssReplyIcon,
                                                      size: 24,
                                                    ),
                                                    title: const LMTextView(
                                                      text: "Reply",
                                                      textStyle: TextStyle(
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                  ListTile(
                                                    onTap: () {
                                                      chatBubbleController
                                                          .hideMenu();
                                                      Clipboard.setData(
                                                        ClipboardData(
                                                          text: TaggingHelper
                                                                  .convertRouteToTag(
                                                                      item.answer) ??
                                                              '',
                                                        ),
                                                      ).then((value) {
                                                        toast(
                                                            "Copied to clipboard");
                                                      });
                                                    },
                                                    leading: const LMIcon(
                                                      type: LMIconType.svg,
                                                      assetPath: ssCopyIcon,
                                                      size: 24,
                                                    ),
                                                    title: const LMTextView(
                                                      text: "Copy",
                                                      textStyle: TextStyle(
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                  // checkEditPermissions(item)
                                                  //     ? ListTile(
                                                  //         onTap: () async {
                                                  //           _convActionBloc
                                                  //               .add(
                                                  //             EditingConversation(
                                                  //               chatroomId:
                                                  //                   chatroom!
                                                  //                       .id,
                                                  //               conversationId:
                                                  //                   item.id,
                                                  //               editConversation:
                                                  //                   item,
                                                  //             ),
                                                  //           );
                                                  //         },
                                                  //         leading:
                                                  //             const LMIcon(
                                                  //           type: LMIconType
                                                  //               .svg,
                                                  //           assetPath:
                                                  //               ssEditIcon,
                                                  //           size: 24,
                                                  //         ),
                                                  //         title:
                                                  //             const LMTextView(
                                                  //           text: "Edit",
                                                  //           textStyle:
                                                  //               TextStyle(
                                                  //             fontSize: 14,
                                                  //           ),
                                                  //         ),
                                                  //       )
                                                  //     : const SizedBox
                                                  //         .shrink(),
                                                  Visibility(
                                                    visible:
                                                        checkDeletePermissions(
                                                            item),
                                                    child: ListTile(
                                                      onTap: () async {
                                                        chatBubbleController
                                                            .hideMenu();
                                                        if ((localTopic !=
                                                                    null &&
                                                                localTopic!
                                                                        .id ==
                                                                    item.id) ||
                                                            (chatroom!.topic !=
                                                                    null &&
                                                                item.id ==
                                                                    chatroom!
                                                                        .topic!
                                                                        .id)) {
                                                          showDialog(
                                                            context: context,
                                                            builder:
                                                                (context) =>
                                                                    AlertDialog(
                                                              title: const Text(
                                                                  "Delete Message?"),
                                                              content: const Text(
                                                                  "Are you sure you want to delete this message? The message has been set as current topic of this chatroom"),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed:
                                                                      () {
                                                                    Navigator.pop(
                                                                        context);
                                                                  },
                                                                  child: const LMTextView(
                                                                      text:
                                                                          "CANCEL"),
                                                                ),
                                                                TextButton(
                                                                  onPressed:
                                                                      () {
                                                                    DeleteConversationRequest
                                                                        request =
                                                                        (DeleteConversationRequestBuilder()
                                                                              ..conversationIds([
                                                                                item.id
                                                                              ])
                                                                              ..reason("Delete"))
                                                                            .build();
                                                                    _convActionBloc.add(
                                                                        DeleteConversation(
                                                                            request));
                                                                  },
                                                                  child: const LMTextView(
                                                                      text:
                                                                          "DELETE"),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                        } else {
                                                          DeleteConversationRequest
                                                              request =
                                                              (DeleteConversationRequestBuilder()
                                                                    ..conversationIds([
                                                                      item.id
                                                                    ])
                                                                    ..reason(
                                                                        "Delete"))
                                                                  .build();
                                                          _convActionBloc.add(
                                                              DeleteConversation(
                                                                  request));
                                                        }
                                                      },
                                                      leading: const LMIcon(
                                                        type: LMIconType.svg,
                                                        assetPath: ssDeleteIcon,
                                                        color: Colors.red,
                                                        size: 24,
                                                      ),
                                                      title: const LMTextView(
                                                        text: "Delete",
                                                        textStyle: TextStyle(
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        onReply: (replyingTo) {
                                          int userId =
                                              item.userId ?? item.memberId!;
                                          if (userId == user!.id) {
                                            item.member = user!;
                                          }
                                          if (item.deletedByUserId != null) {
                                            return;
                                          }
                                          _convActionBloc.add(
                                            ReplyConversation(
                                              chatroomId: chatroom!.id,
                                              conversationId: item.id,
                                              replyConversation: replyingTo,
                                            ),
                                          );
                                        },
                                        avatar: LMProfilePicture(
                                          fallbackText: item.member!.name,
                                          imageUrl: item.member!.imageUrl,
                                          size: 24,
                                        ),
                                        outsideTitle: LMTextView(
                                          text: item.member!.name,
                                          textStyle: const TextStyle(
                                            fontSize: 10,
                                            color:
                                                Color.fromRGBO(71, 85, 105, 1),
                                          ),
                                        ),
                                        outsideFooter: LMTextView(
                                          text: item.createdAt,
                                          textStyle: const TextStyle(
                                            fontSize: 10,
                                            color:
                                                Color.fromRGBO(71, 85, 105, 1),
                                          ),
                                        ),
                                        mediaWidget:
                                            item.deletedByUserId == null
                                                ? getContent(item)
                                                : null,
                                        content: LMChatContent(
                                          conversation: item,
                                          visibleLines: 2,
                                          animation: true,
                                          textStyle: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                          tagStyle: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: secondary.shade600,
                                          ),
                                          linkStyle: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: secondary.shade600,
                                          ),
                                        ),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(16),
                                          topRight: Radius.circular(16),
                                          bottomLeft: Radius.zero,
                                          bottomRight: Radius.circular(16),
                                        ),
                                        conversation: item,
                                        replyingTo: replyConversation,
                                        replyItem: LMReplyItem(
                                          replyToConversation:
                                              replyConversation,
                                          borderRadius: 10,
                                          highlightColor: secondary,
                                          title: replyConversation != null
                                              ? LMTextView(
                                                  text: userMeta[
                                                          replyConversation
                                                                  .userId ??
                                                              replyConversation
                                                                  .memberId!]!
                                                      .name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                  textStyle: const TextStyle(
                                                    color: kPrimaryColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                )
                                              : null,
                                          subtitle: replyConversation != null
                                              ? replyConversation
                                                          .deletedByUserId !=
                                                      null
                                                  ? getDeletedTextWidget(
                                                      replyConversation, user!)
                                                  : getChatItemAttachmentTile(
                                                      replyAttachments ?? [],
                                                      replyConversation,
                                                    )
                                              : null,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                              .withOpacity(0.7),
                                        ),
                                        sender: userMeta[
                                                item.userId ?? item.memberId] ??
                                            item.member!,
                                      );
                              },
                            ),
                          );
                        });
                  },
                );

                return Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: kWhiteColor.withOpacity(1),
                        // boxShadow: [
                        //   BoxShadow(
                        //     color: Colors.black.withOpacity(1),
                        //     blurRadius: 5,
                        //     offset: const Offset(4, 2),
                        //   )
                        // ],
                      ),
                      child: Column(
                        children: <Widget>[
                          kVerticalPaddingMedium,
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4.w,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                BackButton(
                                  onPressed: () {
                                    _chatroomActionBloc.add(
                                      MarkReadChatroomEvent(
                                          chatroomId: widget.chatroomId),
                                    );
                                    BlocProvider.of<HomeBloc>(context)
                                        .add(UpdateHomeEvent());

                                    router.pop();
                                  },
                                  style: ButtonStyle(
                                    padding: MaterialStateProperty.all(
                                      EdgeInsets.zero,
                                    ),
                                    fixedSize: MaterialStateProperty.all(
                                      const Size(24, 24),
                                    ),
                                  ),
                                ),
                                LMProfilePicture(
                                  fallbackText: chatroom!.header,
                                  imageUrl: chatroom?.chatroomImageUrl,
                                  size: 36,
                                ),
                                SizedBox(width: 2.w),
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      chatroom != null
                                          ? showBottomSheet(
                                              context: context,
                                              builder: (context) {
                                                return LMGroupDetailBottomSheet(
                                                  chatRoom: chatroom!,
                                                  backgroundColor: Colors.white
                                                      .withOpacity(0.9),
                                                );
                                              },
                                            )
                                          : {};
                                    },
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        LMTextView(
                                          text: chatroom!.header,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textStyle: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        kVerticalPaddingXSmall,
                                        LMTextView(
                                          text:
                                              '${chatroom!.participantCount} participants',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textStyle: const TextStyle(
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                ChatroomMenu(
                                  chatroom: chatroom!,
                                  chatroomActions: state
                                      .getChatroomResponse.chatroomActions!,
                                ),
                                kHorizontalPaddingMedium,
                              ],
                            ),
                          ),
                          const Divider(
                            height: 1,
                          ),
                          BlocListener<ChatroomActionBloc, ChatroomActionState>(
                            listener: (context, state) {
                              if (state is ChatroomTopicSet) {
                                localTopic = state.topic;
                                if (!showChatTopic) showChatTopic = true;
                                rebuildChatTopic.value =
                                    !rebuildChatTopic.value;
                              }
                            },
                            child: ValueListenableBuilder(
                              valueListenable: rebuildChatTopic,
                              builder: (context, value, child) {
                                if (chatroom!.topic != null && showChatTopic) {
                                  return LMChatRoomTopic(
                                      backGroundColor: secondary.shade100,
                                      leading: const VerticalDivider(
                                        color: kPrimaryColor,
                                        thickness: 3,
                                      ),
                                      trailing: Transform.rotate(
                                        angle: math.pi / 4,
                                        child:
                                            const Icon(Icons.push_pin_outlined),
                                      ),
                                      conversation:
                                          localTopic ?? chatroom!.topic,
                                      onTap: () {});
                                } else {
                                  return const SizedBox.shrink();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: kWhiteColor.withOpacity(1),
                          // boxShadow: [
                          //   BoxShadow(
                          //     color: Colors.black.withOpacity(1),
                          //     blurRadius: 2,
                          //     offset: const Offset(0, 2),
                          //   )
                          // ],
                        ),
                        child: pagedListView,
                      ),
                    ),
                    BlocConsumer(
                        bloc: _convActionBloc,
                        listener: (context, state) {
                          if (state is ConversationDelete) {
                            updateDeletedConversation(
                                state.deleteConversationResponse);
                          }

                          if (state is ConversationEdited) {
                            updateEditedConversation(
                                state.editConversationResponse.conversation!);
                          }
                          if (state is ReplyConversationState) {
                            rebuildChatBar.value = !rebuildChatBar.value;
                          }
                          if (state is EditConversationState) {
                            rebuildChatBar.value = !rebuildChatBar.value;
                          }
                        },
                        builder: (context, state) {
                          return ValueListenableBuilder(
                              valueListenable: rebuildChatBar,
                              builder: (context, _, __) {
                                if (state is EditConversationState) {
                                  return ChatBar(
                                    chatroom: chatroom!,
                                    editConversation: state.editConversation,
                                    scrollToBottom: _scrollToBottom,
                                    userMeta: userMeta,
                                  );
                                }
                                if (state is ReplyConversationState) {
                                  return ChatBar(
                                    chatroom: chatroom!,
                                    replyToConversation: state.conversation,
                                    replyConversationAttachments:
                                        conversationAttachmentsMeta.containsKey(
                                                state.conversation.id
                                                    .toString())
                                            ? conversationAttachmentsMeta[
                                                '${state.conversation.id}']
                                            : null,
                                    scrollToBottom: _scrollToBottom,
                                    userMeta: userMeta,
                                  );
                                }
                                return ChatBar(
                                  chatroom: chatroom!,
                                  scrollToBottom: _scrollToBottom,
                                  userMeta: userMeta,
                                );
                              });
                        }),
                  ],
                );
              }
              return Container(
                color: kGreyColor.withOpacity(0.2),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget? getContent(Conversation conversation) {
    if (conversation.attachmentsUploaded == null ||
        !conversation.attachmentsUploaded!) {
      // If conversation has media but not uploaded yet
      // show local files
      Widget? mediaWidget;

      if (mediaFiles[conversation.temporaryId] == null ||
          mediaFiles[conversation.temporaryId]!.isEmpty) {
        // return expandableText;
        if (conversation.ogTags != null) {
          return LMLinkPreview(
              onTap: () {
                launchUrl(
                  Uri.parse(conversation.ogTags?['url'] ?? ''),
                  mode: LaunchMode.externalApplication,
                );
              },
              linkModel: MediaModel(
                  mediaType: LMMediaType.link,
                  ogTags: OgTags.fromEntity(
                      OgTagsEntity.fromJson(conversation.ogTags))));
        } else {
          return null;
        }
      }
      if (mediaFiles[conversation.temporaryId]!.first.mediaType ==
              MediaType.photo ||
          mediaFiles[conversation.temporaryId]!.first.mediaType ==
              MediaType.video) {
        mediaWidget =
            getImageFileMessage(context, mediaFiles[conversation.temporaryId]!);
      } else if (mediaFiles[conversation.temporaryId]!.first.mediaType ==
          MediaType.document) {
        mediaWidget =
            documentPreviewFactory(mediaFiles[conversation.temporaryId]!);
      } else if (mediaFiles[conversation.temporaryId]!.first.mediaType ==
          MediaType.link) {
        mediaWidget = LMLinkPreview(
            onTap: () {
              launchUrl(
                Uri.parse(
                    mediaFiles[conversation.temporaryId]!.first.ogTags?.url ??
                        ''),
                mode: LaunchMode.externalApplication,
              );
            },
            linkModel: MediaModel(
                mediaType: LMMediaType.link,
                ogTags: mediaFiles[conversation.temporaryId]!.first.ogTags));
      } else {
        mediaWidget = null;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              mediaWidget ?? const SizedBox.shrink(),
              const Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                right: 0,
                child: LMLoader(
                  primary: kWhiteColor,
                ),
              )
            ],
          ),
          conversation.answer.isEmpty
              ? const SizedBox.shrink()
              : kVerticalPaddingXSmall,
        ],
      );
    } else if (conversation.attachmentsUploaded != null ||
        conversation.attachmentsUploaded!) {
      // If conversation has media and uploaded
      // show uploaded files
      final conversationAttachments =
          conversationAttachmentsMeta.containsKey(conversation.id.toString())
              ? conversationAttachmentsMeta['${conversation.id}']
              : null;
      if (conversationAttachments == null) {
        return null;
      }

      Widget? mediaWidget;
      if (conversationAttachments.first.mediaType == MediaType.photo ||
          conversationAttachments.first.mediaType == MediaType.video) {
        mediaWidget = getImageMessage(
          context,
          conversationAttachments,
          chatroom!,
          conversation,
          userMeta,
        );
      } else if (conversationAttachments.first.mediaType ==
          MediaType.document) {
        mediaWidget = documentPreviewFactory(conversationAttachments);
      } else if (conversation.ogTags != null) {
        mediaWidget = LMLinkPreview(
            onTap: () {
              launchUrl(
                Uri.parse(conversation.ogTags?['url'] ?? ''),
                mode: LaunchMode.externalApplication,
              );
            },
            linkModel: MediaModel(
                mediaType: LMMediaType.link,
                ogTags: OgTags.fromEntity(
                    OgTagsEntity.fromJson(conversation.ogTags))));
      } else {
        mediaWidget = null;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          mediaWidget ?? const SizedBox.shrink(),
          conversation.answer.isEmpty
              ? const SizedBox.shrink()
              : kVerticalPaddingXSmall,
        ],
      );
    }
    return null;
  }
}
