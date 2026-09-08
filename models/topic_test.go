package models

import (
	"archive/zip"
	"bytes"
	"errors"
	"testing"
	"time"
)

func TestTopicLifecycleSummariesResourcesTasksSearchAndTrash(t *testing.T) {
	initAssetTestDB(t)

	topic := &Topic{
		Title:    "如何让个人 AI 知识库真正可用？",
		Question: "如何把笔记、书签和文章组织成能支撑决策的证据链？",
		MemberID: 1,
		IsPinned: true,
	}
	if err := CreateTopic(topic); err != nil {
		t.Fatalf("CreateTopic() error = %v", err)
	}
	if topic.TopicID == 0 {
		t.Fatalf("CreateTopic() did not set TopicID")
	}

	summary := &TopicSummary{
		TopicID:   topic.TopicID,
		Content:   "专题应该收集资料、沉淀小结，并推动行动闭环。",
		OrderSort: 10,
	}
	if err := CreateTopicSummary(summary); err != nil {
		t.Fatalf("CreateTopicSummary() error = %v", err)
	}
	if summary.SummaryType != TopicSummaryManual {
		t.Fatalf("manual summary type = %q, want %q", summary.SummaryType, TopicSummaryManual)
	}

	aiSummary := &TopicSummary{
		TopicID:     topic.TopicID,
		Content:     "AI 小结：专题资料已经形成一条可执行的证据链。",
		SummaryType: TopicSummaryAI,
		OrderSort:   20,
	}
	if err := CreateTopicSummary(aiSummary); err != nil {
		t.Fatalf("CreateTopicSummary(ai) error = %v", err)
	}

	task := &Task{Content: "补专题全局搜索测试", DueDate: "2026-06-16", TopicID: topic.TopicID, MemberID: 1}
	if err := CreateTask(task); err != nil {
		t.Fatalf("CreateTask() error = %v", err)
	}
	resource := &TopicResource{
		TopicID:       topic.TopicID,
		ResourceType:  TopicResourceTask,
		TargetID:      task.TaskID,
		TitleSnapshot: task.Content,
	}
	if err := CreateTopicResource(resource); err != nil {
		t.Fatalf("CreateTopicResource(task) error = %v", err)
	}
	if err := CreateTopicResource(resource); !errors.Is(err, ErrTopicResourceDuplicate) {
		t.Fatalf("duplicate CreateTopicResource error = %v, want ErrTopicResourceDuplicate", err)
	}
	summaryComment := &TopicComment{
		TopicID:    topic.TopicID,
		TargetType: TopicCommentSummary,
		TargetID:   summary.SummaryID,
		MemberID:   1,
		Content:    "小结评论",
	}
	if err := CreateTopicComment(summaryComment); err != nil {
		t.Fatalf("CreateTopicComment(summary) error = %v", err)
	}
	if err := CreateTopicComment(&TopicComment{
		TopicID:    topic.TopicID,
		TargetType: TopicCommentSummary,
		TargetID:   summary.SummaryID,
		MemberID:   1,
		Content:    "小结补充评论",
	}); err != nil {
		t.Fatalf("CreateTopicComment(second summary comment) error = %v", err)
	}
	if err := CreateTopicComment(&TopicComment{
		TopicID:    topic.TopicID,
		TargetType: TopicCommentResource,
		TargetID:   resource.TopicResourceID,
		MemberID:   1,
		Content:    "资料评论",
	}); err != nil {
		t.Fatalf("CreateTopicComment(resource) error = %v", err)
	}
	if err := CreateTopicComment(&TopicComment{
		TopicID:    topic.TopicID,
		TargetType: TopicCommentTask,
		TargetID:   task.TaskID,
		MemberID:   1,
		Content:    "待办评论",
	}); err != nil {
		t.Fatalf("CreateTopicComment(task) error = %v", err)
	}

	list, total, err := ListTopics(1, TopicFilter{Keyword: "AI 知识库", Page: 1, PageSize: 20})
	if err != nil {
		t.Fatalf("ListTopics() error = %v", err)
	}
	if total != 1 || len(list) != 1 {
		t.Fatalf("ListTopics total=%d len=%d, want 1", total, len(list))
	}
	if list[0].ResourceCount != 1 || list[0].SummaryCount != 2 || list[0].TaskCount != 1 {
		t.Fatalf("topic stats = resource:%d summary:%d task:%d", list[0].ResourceCount, list[0].SummaryCount, list[0].TaskCount)
	}
	detail, err := GetTopicDetail(topic.TopicID, 1)
	if err != nil {
		t.Fatalf("GetTopicDetail() error = %v", err)
	}
	if detail.Topic.Title != topic.Title || len(detail.Resources) != 1 || len(detail.Summaries) != 2 || len(detail.Tasks) != 1 {
		t.Fatalf("unexpected detail: %#v", detail)
	}
	if detail.Stats.CommentCount != 4 || detail.Resources[0].CommentCount != 1 ||
		detail.Summaries[0].CommentCount != 2 || detail.Tasks[0].CommentCount != 1 {
		t.Fatalf("comment counts before trash restore = %#v", detail)
	}
	if detail.Summaries[0].SummaryType != TopicSummaryManual || detail.Summaries[1].SummaryType != TopicSummaryAI {
		t.Fatalf("summary types = %q, %q", detail.Summaries[0].SummaryType, detail.Summaries[1].SummaryType)
	}

	search, err := GlobalSearch(1, "行动闭环")
	if err != nil {
		t.Fatalf("GlobalSearch() error = %v", err)
	}
	if search.Counts["topics"] != 1 || len(search.Topics) != 1 || search.Topics[0].TopicID != topic.TopicID {
		t.Fatalf("topic search result = %#v", search.Topics)
	}

	if err := DeleteTopic(topic.TopicID, 1); err != nil {
		t.Fatalf("DeleteTopic() error = %v", err)
	}
	if _, err := GetTopicByID(topic.TopicID); err == nil {
		t.Fatalf("deleted topic should not be readable")
	}

	trash, trashTotal, err := ListTrash(1, "topic", 1, 20)
	if err != nil {
		t.Fatalf("ListTrash(topic) error = %v", err)
	}
	if trashTotal != 1 || len(trash) != 1 || trash[0].ResourceName != topic.Title {
		t.Fatalf("topic trash total=%d trash=%v", trashTotal, trash)
	}
	if err := RestoreFromTrash(trash[0].TrashID); err != nil {
		t.Fatalf("RestoreFromTrash(topic) error = %v", err)
	}
	restored, err := GetTopicDetail(topic.TopicID, 1)
	if err != nil {
		t.Fatalf("restored GetTopicDetail() error = %v", err)
	}
	if len(restored.Resources) != 1 || len(restored.Summaries) != 2 || len(restored.Tasks) != 1 {
		t.Fatalf("restored detail = %#v", restored)
	}
	if restored.Summaries[0].SummaryType != TopicSummaryManual || restored.Summaries[1].SummaryType != TopicSummaryAI {
		t.Fatalf("restored summary types = %q, %q", restored.Summaries[0].SummaryType, restored.Summaries[1].SummaryType)
	}
	comments, commentTotal, err := ListTopicComments(topic.TopicID, 1, "", 0, 1, 20)
	if err != nil {
		t.Fatalf("ListTopicComments(restored) error = %v", err)
	}
	if commentTotal != 4 || len(comments) != 4 || restored.Stats.CommentCount != 4 {
		t.Fatalf("restored comments total=%d len=%d stats=%d", commentTotal, len(comments), restored.Stats.CommentCount)
	}
}

func TestTopicCommentTransactionsRejectRepliesAndKeepLegacyCommentsIndependent(t *testing.T) {
	initAssetTestDB(t)

	topic := &Topic{Title: "评论一致性", MemberID: 1}
	if err := CreateTopic(topic); err != nil {
		t.Fatalf("CreateTopic() error = %v", err)
	}
	summary := &TopicSummary{TopicID: topic.TopicID, Content: "评论目标"}
	if err := CreateTopicSummary(summary); err != nil {
		t.Fatalf("CreateTopicSummary() error = %v", err)
	}
	root := &TopicComment{
		TopicID: topic.TopicID, TargetType: TopicCommentSummary,
		TargetID: summary.SummaryID, MemberID: 1, Content: "根评论",
	}
	if err := CreateTopicComment(root); err != nil {
		t.Fatalf("CreateTopicComment(root) error = %v", err)
	}
	if err := CreateTopicComment(&TopicComment{
		TopicID: topic.TopicID, TargetType: TopicCommentSummary,
		TargetID: summary.SummaryID, MemberID: 1,
		ParentCommentID: root.CommentID, Content: "不允许的回复",
	}); !errors.Is(err, ErrTopicCommentReplyUnsupported) {
		t.Fatalf("reply error = %v, want ErrTopicCommentReplyUnsupported", err)
	}

	if _, err := DB.Exec(`CREATE TRIGGER fail_topic_comment_touch
		BEFORE UPDATE ON md_topics BEGIN SELECT RAISE(ABORT, 'touch failed'); END`); err != nil {
		t.Fatalf("create trigger error = %v", err)
	}
	if err := CreateTopicComment(&TopicComment{
		TopicID: topic.TopicID, TargetType: TopicCommentSummary,
		TargetID: summary.SummaryID, MemberID: 1, Content: "必须回滚",
	}); err == nil {
		t.Fatal("CreateTopicComment() should fail when topic touch fails")
	}
	var count int
	if err := DB.QueryRow(`SELECT COUNT(*) FROM md_topic_comments WHERE topic_id = ?`, topic.TopicID).Scan(&count); err != nil {
		t.Fatalf("count comments error = %v", err)
	}
	if count != 1 {
		t.Fatalf("comment count after failed create = %d, want 1", count)
	}
	if _, err := UpdateTopicComment(root.CommentID, topic.TopicID, 1, "必须回滚的更新"); err == nil {
		t.Fatal("UpdateTopicComment() should fail when topic touch fails")
	}
	stored, err := GetTopicCommentByID(root.CommentID, topic.TopicID, 1)
	if err != nil {
		t.Fatalf("GetTopicCommentByID() error = %v", err)
	}
	if stored.Content != "根评论" {
		t.Fatalf("comment content after failed update = %q, want original", stored.Content)
	}
	if _, err := DB.Exec(`DROP TRIGGER fail_topic_comment_touch`); err != nil {
		t.Fatalf("drop trigger error = %v", err)
	}

	now := time.Now()
	legacy, err := DB.Exec(`INSERT INTO md_topic_comments
		(topic_id, target_type, target_id, member_id, parent_comment_id, content, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		topic.TopicID, TopicCommentSummary, summary.SummaryID, 1, root.CommentID,
		"历史回复", now, now)
	if err != nil {
		t.Fatalf("insert legacy reply error = %v", err)
	}
	if legacyID, _ := legacy.LastInsertId(); legacyID == 0 {
		t.Fatal("legacy reply ID = 0")
	}
	comments, total, err := ListTopicComments(topic.TopicID, 1, TopicCommentSummary, summary.SummaryID, 1, 20)
	if err != nil {
		t.Fatalf("ListTopicComments() error = %v", err)
	}
	if total != 2 || len(comments) != 2 || comments[1].ParentCommentID != 0 {
		t.Fatalf("legacy replies should be returned as top-level comments: total=%d comments=%#v", total, comments)
	}
	if err := DeleteTopicComment(root.CommentID, topic.TopicID, 1); err != nil {
		t.Fatalf("DeleteTopicComment(root) error = %v", err)
	}
	if err := DB.QueryRow(`SELECT COUNT(*) FROM md_topic_comments WHERE topic_id = ?`, topic.TopicID).Scan(&count); err != nil {
		t.Fatalf("count comments after delete error = %v", err)
	}
	if count != 1 {
		t.Fatalf("comment count after deleting one comment = %d, want 1", count)
	}
	var parentID int64
	if err := DB.QueryRow(`SELECT parent_comment_id FROM md_topic_comments WHERE topic_id = ?`, topic.TopicID).Scan(&parentID); err != nil {
		t.Fatalf("query preserved legacy comment parent error = %v", err)
	}
	if parentID != 0 {
		t.Fatalf("preserved legacy comment parent_id = %d, want 0", parentID)
	}
}

func TestCreateTablesInitializesCurrentTopicSchema(t *testing.T) {
	initAssetTestDB(t)

	for _, tc := range []struct {
		table string
		col   string
	}{
		{"md_topics", "member_id"},
		{"md_topics", "question"},
		{"md_topic_summaries", "content"},
		{"md_topic_summaries", "summary_type"},
		{"md_topic_resources", "target_id"},
		{"md_topic_comments", "target_type"},
		{"md_topic_comments", "parent_comment_id"},
	} {
		var count int
		if err := DB.QueryRow("SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?", tc.table, tc.col).Scan(&count); err != nil {
			t.Fatalf("inspect %s.%s error = %v", tc.table, tc.col, err)
		}
		if count != 1 {
			t.Fatalf("%s.%s column count = %d, want 1", tc.table, tc.col, count)
		}
	}
}

func TestGlobalSearchFindsTopicWhenOnlySummaryMatchesASCIIKeyword(t *testing.T) {
	initAssetTestDB(t)

	topic := &Topic{
		Title:    "OAuth 调研",
		Question: "如何设计授权流程？",
		MemberID: 1,
	}
	if err := CreateTopic(topic); err != nil {
		t.Fatalf("CreateTopic() error = %v", err)
	}
	if err := CreateTopicSummary(&TopicSummary{
		TopicID: topic.TopicID,
		Content: "PKCE retry strategy and backoff details for failed token exchange.",
	}); err != nil {
		t.Fatalf("CreateTopicSummary() error = %v", err)
	}

	search, err := GlobalSearch(1, "retry")
	if err != nil {
		t.Fatalf("GlobalSearch() error = %v", err)
	}
	if search.Counts["topics"] != 1 || len(search.Topics) != 1 || search.Topics[0].TopicID != topic.TopicID {
		t.Fatalf("topic summary search result = %#v", search.Topics)
	}
}

func TestTopicExportImportRoundTrip(t *testing.T) {
	initAssetTestDB(t)

	topic := &Topic{
		Title:    "专题导入导出",
		Question: "确认专题标题、问题、小结、待办和资料都能迁移。",
		MemberID: 1,
		IsPinned: true,
	}
	if err := CreateTopic(topic); err != nil {
		t.Fatalf("CreateTopic() error = %v", err)
	}
	summary := &TopicSummary{
		TopicID:     topic.TopicID,
		Content:     "第一阶段小结",
		SummaryType: TopicSummaryAI,
		OrderSort:   7,
	}
	if err := CreateTopicSummary(summary); err != nil {
		t.Fatalf("CreateTopicSummary() error = %v", err)
	}
	task := &Task{Content: "专题迁移待办", DueDate: "2026-07-01", TopicID: topic.TopicID, MemberID: 1}
	if err := CreateTask(task); err != nil {
		t.Fatalf("CreateTask() error = %v", err)
	}
	resource := &TopicResource{
		TopicID:       topic.TopicID,
		ResourceType:  TopicResourceTask,
		TargetID:      task.TaskID,
		TitleSnapshot: task.Content,
		DescSnapshot:  "迁移资料描述",
		OrderSort:     3,
	}
	if err := CreateTopicResource(resource); err != nil {
		t.Fatalf("CreateTopicResource() error = %v", err)
	}
	rootComment := &TopicComment{
		TopicID: topic.TopicID, TargetType: TopicCommentSummary, TargetID: summary.SummaryID,
		MemberID: 1, Content: "小结评论",
	}
	if err := CreateTopicComment(rootComment); err != nil {
		t.Fatalf("CreateTopicComment(summary) error = %v", err)
	}
	if err := CreateTopicComment(&TopicComment{
		TopicID: topic.TopicID, TargetType: TopicCommentSummary, TargetID: summary.SummaryID,
		MemberID: 1, Content: "小结补充评论",
	}); err != nil {
		t.Fatalf("CreateTopicComment(second summary comment) error = %v", err)
	}
	if err := CreateTopicComment(&TopicComment{
		TopicID: topic.TopicID, TargetType: TopicCommentResource, TargetID: resource.TopicResourceID,
		MemberID: 1, Content: "资料评论",
	}); err != nil {
		t.Fatalf("CreateTopicComment(resource) error = %v", err)
	}
	if err := CreateTopicComment(&TopicComment{
		TopicID: topic.TopicID, TargetType: TopicCommentTask, TargetID: task.TaskID,
		MemberID: 1, Content: "待办评论",
	}); err != nil {
		t.Fatalf("CreateTopicComment(task) error = %v", err)
	}

	exported, err := ExportAllData(1)
	if err != nil {
		t.Fatalf("ExportAllData() error = %v", err)
	}
	if len(exported.Topics) != 1 || exported.Manifest.Stats.Topics != 1 {
		t.Fatalf("exported topics len=%d stats=%d, want 1", len(exported.Topics), exported.Manifest.Stats.Topics)
	}
	if len(exported.Topics[0].Summaries) != 1 || len(exported.Topics[0].Resources) != 1 {
		t.Fatalf("exported topic detail = %#v", exported.Topics[0])
	}
	if len(exported.Topics[0].Comments) != 4 {
		t.Fatalf("exported topic comments=%d, want 4", len(exported.Topics[0].Comments))
	}
	if exported.Tasks[0].TopicID != topic.TopicID {
		t.Fatalf("exported task topic_id=%d, want %d", exported.Tasks[0].TopicID, topic.TopicID)
	}

	zipBuf, err := BuildExportZip(exported)
	if err != nil {
		t.Fatalf("BuildExportZip() error = %v", err)
	}
	zr, err := zip.NewReader(bytes.NewReader(zipBuf.Bytes()), int64(zipBuf.Len()))
	if err != nil {
		t.Fatalf("zip.NewReader() error = %v", err)
	}
	parsed, err := ParseImportData(zr)
	if err != nil {
		t.Fatalf("ParseImportData() error = %v", err)
	}
	if len(parsed.Topics) != 1 {
		t.Fatalf("parsed topics len=%d, want 1", len(parsed.Topics))
	}

	result, err := ImportExecuteData(parsed, 2, nil, "")
	if err != nil {
		t.Fatalf("ImportExecuteData() error = %v", err)
	}
	if result.TopicsImported != 1 || result.TasksImported != 1 {
		t.Fatalf("import result topics=%d tasks=%d errors=%v", result.TopicsImported, result.TasksImported, result.Errors)
	}
	importedTopics, total, err := ListTopics(2, TopicFilter{Keyword: "专题导入导出", Page: 1, PageSize: 10})
	if err != nil {
		t.Fatalf("ListTopics(imported) error = %v", err)
	}
	if total != 1 || len(importedTopics) != 1 {
		t.Fatalf("imported topics total=%d topics=%v", total, importedTopics)
	}
	detail, err := GetTopicDetail(importedTopics[0].TopicID, 2)
	if err != nil {
		t.Fatalf("GetTopicDetail(imported) error = %v", err)
	}
	if detail.Topic.Question != topic.Question || len(detail.Summaries) != 1 || len(detail.Resources) != 1 || len(detail.Tasks) != 1 {
		t.Fatalf("imported detail = %#v", detail)
	}
	if detail.Resources[0].TargetID != detail.Tasks[0].TaskID {
		t.Fatalf("imported topic resource target=%d, want imported task %d", detail.Resources[0].TargetID, detail.Tasks[0].TaskID)
	}
	comments, totalComments, err := ListTopicComments(importedTopics[0].TopicID, 2, "", 0, 1, 20)
	if err != nil {
		t.Fatalf("ListTopicComments(imported) error = %v", err)
	}
	if totalComments != 4 || len(comments) != 4 || detail.Stats.CommentCount != 4 {
		t.Fatalf("imported comments total=%d len=%d stats=%d", totalComments, len(comments), detail.Stats.CommentCount)
	}
}
