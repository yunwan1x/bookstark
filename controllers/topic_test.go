package controllers_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestTopicsPageUsesCollectionsNavigation(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodGet, "/topics", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /topics status = %d body=%s", w.Code, w.Body.String())
	}
	body := w.Body.String()
	for _, required := range []string{
		`data-header-menu-id="header-collections-menu"`,
		`href="/topics"`,
		`href="/labels"`,
		`专题`,
	} {
		if !strings.Contains(body, required) {
			t.Fatalf("topics page should render collections navigation containing %q", required)
		}
	}
	for _, forbidden := range []string{
		`data-nav-id="topics-primary"`,
		`data-nav-id="knowledge-menu-topics"`,
		`id="header-collections-menu" class="header-dropdown hidden" role="menu">
                <div class="header-dropdown-panel">
                    <a href="/shares"`,
	} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("topics page should not render old navigation marker %q", forbidden)
		}
	}
}

func TestTopicAPIs(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodGet, "/topics", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /topics status = %d body=%s", w.Code, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/topics", map[string]any{
		"title":     "如何让个人 AI 知识库真正可用？",
		"question":  "如何把笔记、书签和文章组织成能支撑决策的证据链？",
		"is_pinned": true,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/topics status = %d body=%s", w.Code, w.Body.String())
	}
	var created topicResponse
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode topic response: %v", err)
	}
	if created.Data.TopicID == 0 || created.Data.Title == "" || !created.Data.IsPinned {
		t.Fatalf("unexpected created topic: %s", w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/topics/"+itoa(created.Data.TopicID)+"/summaries", map[string]any{
		"content": "专题应该作为内容组织层。",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/topics/:id/summaries status = %d body=%s", w.Code, w.Body.String())
	}
	var manualSummary topicSummaryResponse
	if err := json.Unmarshal(w.Body.Bytes(), &manualSummary); err != nil {
		t.Fatalf("decode manual summary response: %v", err)
	}
	if manualSummary.Data.SummaryType != "manual" {
		t.Fatalf("manual summary type = %q body=%s", manualSummary.Data.SummaryType, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/topics/"+itoa(created.Data.TopicID)+"/summaries", map[string]any{
		"content":      "AI 小结：专题资料和待办已经形成闭环。",
		"summary_type": "ai",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/topics/:id/summaries ai status = %d body=%s", w.Code, w.Body.String())
	}
	var aiSummary topicSummaryResponse
	if err := json.Unmarshal(w.Body.Bytes(), &aiSummary); err != nil {
		t.Fatalf("decode ai summary response: %v", err)
	}
	if aiSummary.Data.SummaryType != "ai" {
		t.Fatalf("ai summary type = %q body=%s", aiSummary.Data.SummaryType, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/tasks", map[string]any{
		"content":  "补专题 API 测试",
		"due_date": "2026-06-16",
		"topic_id": created.Data.TopicID,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/tasks status = %d body=%s", w.Code, w.Body.String())
	}
	var task taskResponse
	if err := json.Unmarshal(w.Body.Bytes(), &task); err != nil {
		t.Fatalf("decode task response: %v", err)
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/topics/"+itoa(created.Data.TopicID)+"/resources", map[string]any{
		"resource_type":  "task",
		"target_id":      task.Data.TaskID,
		"title_snapshot": task.Data.Content,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/topics/:id/resources status = %d body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodPost, "/api/topics/"+itoa(created.Data.TopicID)+"/resources", map[string]any{
		"resource_type":  "task",
		"target_id":      task.Data.TaskID,
		"title_snapshot": task.Data.Content,
	})
	if w.Code != http.StatusConflict {
		t.Fatalf("duplicate resource status = %d body=%s", w.Code, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodGet, "/api/topics/"+itoa(created.Data.TopicID), nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /api/topics/:id status = %d body=%s", w.Code, w.Body.String())
	}
	var detail topicDetailResponse
	if err := json.Unmarshal(w.Body.Bytes(), &detail); err != nil {
		t.Fatalf("decode detail response: %v", err)
	}
	if detail.Data.Topic.TopicID != created.Data.TopicID || detail.Data.Stats.ResourceCount != 1 || detail.Data.Stats.SummaryCount != 2 || detail.Data.Stats.TaskCount != 1 {
		t.Fatalf("unexpected topic detail: %s", w.Body.String())
	}
	if len(detail.Data.Summaries) != 2 || detail.Data.Summaries[0].SummaryType != "manual" || detail.Data.Summaries[1].SummaryType != "ai" {
		t.Fatalf("unexpected summary types in detail: %s", w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodGet, "/api/topics?keyword=AI", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /api/topics status = %d body=%s", w.Code, w.Body.String())
	}
	var list topicListResponse
	if err := json.Unmarshal(w.Body.Bytes(), &list); err != nil {
		t.Fatalf("decode list response: %v", err)
	}
	if list.Total != 1 || len(list.Data) != 1 || list.Data[0].ResourceCount != 1 || list.Data[0].TaskCount != 1 {
		t.Fatalf("unexpected topic list: %s", w.Body.String())
	}
}

func TestCreateTopicResourceRejectsReferenceTypesWithoutTargetID(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/topics", map[string]any{
		"title": "行动项引用校验",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/topics status = %d body=%s", w.Code, w.Body.String())
	}
	var created topicResponse
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode topic response: %v", err)
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/topics/"+itoa(created.Data.TopicID)+"/resources", map[string]any{
		"resource_type":  "task",
		"title_snapshot": "没有真实待办 ID 的假行动项",
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("POST fake task topic resource status = %d body=%s", w.Code, w.Body.String())
	}
}

func TestTopicTrashAPIListsDeletedTopics(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/topics", map[string]any{
		"title":    "进入回收站的专题",
		"question": "专题删除后应该出现在回收站专题 tab",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/topics status = %d body=%s", w.Code, w.Body.String())
	}
	var created topicResponse
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode topic response: %v", err)
	}

	w = adminAssetRequest(router, token, http.MethodDelete, "/api/topics/"+itoa(created.Data.TopicID), nil)
	if w.Code != http.StatusOK {
		t.Fatalf("DELETE /api/topics/:id status = %d body=%s", w.Code, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodGet, "/api/trash?type=topic", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /api/trash?type=topic status = %d body=%s", w.Code, w.Body.String())
	}
	var trash topicTrashListResponse
	if err := json.Unmarshal(w.Body.Bytes(), &trash); err != nil {
		t.Fatalf("decode topic trash response: %v", err)
	}
	if trash.Total != 1 || len(trash.Data) != 1 || trash.Data[0].ResourceType != "topic" || trash.Data[0].ResourceName != "进入回收站的专题" {
		t.Fatalf("unexpected topic trash response: %s", w.Body.String())
	}
}

func TestTopicCommentAPIs(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/topics", map[string]any{"title": "专题评论 API"})
	var topic topicResponse
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &topic) != nil {
		t.Fatalf("create topic status=%d body=%s", w.Code, w.Body.String())
	}
	base := "/api/topics/" + itoa(topic.Data.TopicID)
	w = adminAssetRequest(router, token, http.MethodPost, base+"/summaries", map[string]any{"content": "可评论的小结"})
	var summary topicSummaryResponse
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &summary) != nil {
		t.Fatalf("create summary status=%d body=%s", w.Code, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodPost, base+"/comments", map[string]any{
		"target_type": "summary", "target_id": summary.Data.SummaryID, "content": "第一条 **Markdown** 评论",
	})
	var root topicCommentResponse
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &root) != nil || root.Data.CommentID == 0 {
		t.Fatalf("create comment status=%d body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodPost, base+"/comments", map[string]any{
		"target_type": "summary", "target_id": summary.Data.SummaryID,
		"parent_comment_id": root.Data.CommentID, "content": "回复",
	})
	if w.Code != http.StatusBadRequest || !strings.Contains(w.Body.String(), "只支持一级评论") {
		t.Fatalf("reply should be rejected: status=%d body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodPost, base+"/comments", map[string]any{
		"target_type": "summary", "target_id": summary.Data.SummaryID, "content": "第二条一级评论",
	})
	var second topicCommentResponse
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &second) != nil || second.Data.CommentID == 0 {
		t.Fatalf("create second comment status=%d body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodPost, base+"/comments", map[string]any{
		"target_type": "summary", "target_id": summary.Data.SummaryID + 9999, "content": "不应写入",
	})
	if w.Code != http.StatusNotFound {
		t.Fatalf("invalid target status=%d body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodPost, base+"/comments", map[string]any{
		"target_type": "summary", "target_id": summary.Data.SummaryID, "content": strings.Repeat("x", 256<<10),
	})
	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized comment request status=%d body=%s", w.Code, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodGet, base+"/comments?target_type=summary&target_id="+itoa(summary.Data.SummaryID)+"&page_size=0", nil)
	var list topicCommentListResponse
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &list) != nil || list.Total != 2 || list.PageSize != 100 {
		t.Fatalf("list comments status=%d body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodPut, base+"/comments/"+itoa(root.Data.CommentID), map[string]any{"content": "更新后的评论"})
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), "更新后的评论") {
		t.Fatalf("update comment status=%d body=%s", w.Code, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodGet, base, nil)
	var detail topicDetailResponse
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &detail) != nil {
		t.Fatalf("get detail status=%d body=%s", w.Code, w.Body.String())
	}
	if detail.Data.Stats.CommentCount != 2 || len(detail.Data.Summaries) != 1 || detail.Data.Summaries[0].CommentCount != 2 {
		t.Fatalf("unexpected comment counts: %s", w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodDelete, base+"/comments/"+itoa(root.Data.CommentID), nil)
	if w.Code != http.StatusOK {
		t.Fatalf("delete comment status=%d body=%s", w.Code, w.Body.String())
	}
	w = adminAssetRequest(router, token, http.MethodGet, base+"/comments?target_type=summary&target_id="+itoa(summary.Data.SummaryID), nil)
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &list) != nil || list.Total != 1 {
		t.Fatalf("deleting one comment should preserve other comments: status=%d body=%s", w.Code, w.Body.String())
	}
}

type topicResponse struct {
	Code int `json:"code"`
	Data struct {
		TopicID  int64  `json:"topic_id"`
		Title    string `json:"title"`
		IsPinned bool   `json:"is_pinned"`
	} `json:"data"`
}

type topicListResponse struct {
	Code int `json:"code"`
	Data []struct {
		TopicID       int64  `json:"topic_id"`
		Title         string `json:"title"`
		ResourceCount int    `json:"resource_count"`
		SummaryCount  int    `json:"summary_count"`
		TaskCount     int    `json:"task_count"`
	} `json:"data"`
	Total int64 `json:"total"`
}

type topicDetailResponse struct {
	Code int `json:"code"`
	Data struct {
		Topic struct {
			TopicID int64  `json:"topic_id"`
			Title   string `json:"title"`
		} `json:"topic"`
		Resources []struct {
			TopicResourceID int64  `json:"topic_resource_id"`
			ResourceType    string `json:"resource_type"`
			TargetID        int64  `json:"target_id"`
			TitleSnapshot   string `json:"title_snapshot"`
			CommentCount    int    `json:"comment_count"`
		} `json:"resources"`
		Summaries []struct {
			SummaryID    int64  `json:"summary_id"`
			Content      string `json:"content"`
			SummaryType  string `json:"summary_type"`
			CommentCount int    `json:"comment_count"`
		} `json:"summaries"`
		Tasks []struct {
			TaskID       int64 `json:"task_id"`
			CommentCount int   `json:"comment_count"`
		} `json:"tasks"`
		Stats struct {
			ResourceCount int `json:"resource_count"`
			SummaryCount  int `json:"summary_count"`
			TaskCount     int `json:"task_count"`
			CommentCount  int `json:"comment_count"`
		} `json:"stats"`
	} `json:"data"`
}

type topicSummaryResponse struct {
	Code int `json:"code"`
	Data struct {
		SummaryID   int64  `json:"summary_id"`
		Content     string `json:"content"`
		SummaryType string `json:"summary_type"`
	} `json:"data"`
}

type topicTrashListResponse struct {
	Code int `json:"code"`
	Data []struct {
		TrashID      int64  `json:"trash_id"`
		ResourceType string `json:"resource_type"`
		ResourceName string `json:"resource_name"`
	} `json:"data"`
	Total int64 `json:"total"`
}

type topicCommentResponse struct {
	Code int `json:"code"`
	Data struct {
		CommentID int64  `json:"comment_id"`
		Content   string `json:"content"`
	} `json:"data"`
}

type topicCommentListResponse struct {
	Code     int                      `json:"code"`
	Data     []map[string]interface{} `json:"data"`
	Total    int64                    `json:"total"`
	PageSize int                      `json:"page_size"`
}
