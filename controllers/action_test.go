package controllers_test

import (
	"encoding/json"
	"net/http"
	"strconv"
	"testing"
	"time"

	"bookstark/models"
)

func TestTaskAPIs(t *testing.T) {
	router, token := initAssetControllerTest(t)

	w := adminAssetRequest(router, token, http.MethodPost, "/api/tasks", map[string]any{
		"content":  "重新设计待办模型",
		"due_date": "2026-06-12",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST /api/tasks status = %d, body=%s", w.Code, w.Body.String())
	}
	var parentResp taskResponse
	if err := json.Unmarshal(w.Body.Bytes(), &parentResp); err != nil {
		t.Fatalf("decode parent response: %v", err)
	}
	if parentResp.Code != 0 || parentResp.Data.TaskID == 0 || parentResp.Data.Content != "重新设计待办模型" {
		t.Fatalf("unexpected parent response: %s", w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodPost, "/api/tasks", map[string]any{
		"content":   "补子待办接口测试",
		"parent_id": parentResp.Data.TaskID,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("POST child /api/tasks status = %d, body=%s", w.Code, w.Body.String())
	}
	var childResp taskResponse
	if err := json.Unmarshal(w.Body.Bytes(), &childResp); err != nil {
		t.Fatalf("decode child response: %v", err)
	}
	if childResp.Data.ParentID != parentResp.Data.TaskID {
		t.Fatalf("child parent_id = %d, want %d", childResp.Data.ParentID, parentResp.Data.TaskID)
	}
	if childResp.Data.DueDate == "" {
		t.Fatalf("child due_date should default when omitted")
	}
	if _, err := time.Parse("2006-01-02", childResp.Data.DueDate); err != nil {
		t.Fatalf("child default due_date %q is not YYYY-MM-DD: %v", childResp.Data.DueDate, err)
	}

	parent, err := models.GetTaskByID(parentResp.Data.TaskID)
	if err != nil {
		t.Fatalf("GetTaskByID(parent) error = %v", err)
	}
	if parent.ChildTotal != 1 || parent.ChildDone != 0 {
		t.Fatalf("parent children = %d/%d, want 0/1 done", parent.ChildDone, parent.ChildTotal)
	}

	children, total, err := models.ListTasks(parent.MemberID, models.TaskFilter{ParentID: parentResp.Data.TaskID, ParentSet: true, Page: 1, PageSize: 20})
	if err != nil {
		t.Fatalf("ListTasks(children) error = %v", err)
	}
	if total != 1 || len(children) != 1 || children[0].TaskID != childResp.Data.TaskID {
		t.Fatalf("children total=%d tasks=%v, want child %d", total, children, childResp.Data.TaskID)
	}

	w = adminAssetRequest(router, token, http.MethodPatch, "/api/tasks/"+itoa(childResp.Data.TaskID)+"/done", map[string]any{"done": true})
	if w.Code != http.StatusOK {
		t.Fatalf("PATCH /api/tasks/:id/done status = %d, body=%s", w.Code, w.Body.String())
	}
	child, err := models.GetTaskByID(childResp.Data.TaskID)
	if err != nil {
		t.Fatalf("GetTaskByID(child after done) error = %v", err)
	}
	if !child.Done || child.CompleteTime == nil {
		t.Fatalf("child done=%v complete=%v, want done with complete_time", child.Done, child.CompleteTime)
	}
	w = adminAssetRequest(router, token, http.MethodPut, "/api/tasks/"+itoa(childResp.Data.TaskID), map[string]any{
		"content":   "补子待办接口测试",
		"due_date":  "",
		"done":      true,
		"parent_id": parentResp.Data.TaskID,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("PUT child with empty due_date status = %d, body=%s", w.Code, w.Body.String())
	}
	child, err = models.GetTaskByID(childResp.Data.TaskID)
	if err != nil {
		t.Fatalf("GetTaskByID(child after empty due_date update) error = %v", err)
	}
	if child.DueDate == "" {
		t.Fatalf("empty due_date update should keep a default due date")
	}
	parent, err = models.GetTaskByID(parentResp.Data.TaskID)
	if err != nil {
		t.Fatalf("GetTaskByID(parent after child done) error = %v", err)
	}
	if parent.ChildTotal != 1 || parent.ChildDone != 1 {
		t.Fatalf("parent children = %d/%d, want 1/1 done", parent.ChildDone, parent.ChildTotal)
	}

	doneTasks, doneTotal, err := models.ListTasks(parent.MemberID, models.TaskFilter{Done: boolPtr(true), Page: 1, PageSize: 20})
	if err != nil {
		t.Fatalf("ListTasks(done) error = %v", err)
	}
	if doneTotal != 1 || len(doneTasks) != 1 || doneTasks[0].TaskID != childResp.Data.TaskID {
		t.Fatalf("done total=%d tasks=%v, want child %d", doneTotal, doneTasks, childResp.Data.TaskID)
	}

	notDueTasks, notDueTotal, err := models.ListTasks(parent.MemberID, models.TaskFilter{DueAfter: "2026-06-10", Page: 1, PageSize: 20})
	if err != nil {
		t.Fatalf("ListTasks(due_after) error = %v", err)
	}
	if notDueTotal != 2 || len(notDueTasks) != 2 {
		t.Fatalf("due_after total=%d tasks=%v, want parent and child", notDueTotal, notDueTasks)
	}

	searchResult, err := models.GlobalSearch(parent.MemberID, "补子待办接口测试")
	if err != nil {
		t.Fatalf("GlobalSearch(tasks) error = %v", err)
	}
	if searchResult.Counts["tasks"] != 1 || len(searchResult.Tasks) != 1 || searchResult.Tasks[0].TaskID != childResp.Data.TaskID {
		t.Fatalf("task search result = %#v, want child task", searchResult.Tasks)
	}

	exported, err := models.ExportAllData(parent.MemberID)
	if err != nil {
		t.Fatalf("ExportAllData() error = %v", err)
	}
	if len(exported.Tasks) < 2 || exported.Manifest.Stats.Tasks < 2 {
		t.Fatalf("exported tasks len=%d stats=%d, want at least 2", len(exported.Tasks), exported.Manifest.Stats.Tasks)
	}

	importResult, err := models.ImportExecuteData(&models.ExportData{Tasks: []models.ExportTask{
		{TaskID: 1001, Content: "导入父待办", DueDate: "2026-06-20"},
		{TaskID: 1002, Content: "导入子待办", ParentID: 1001},
	}}, parent.MemberID, nil, "")
	if err != nil {
		t.Fatalf("ImportExecuteData(tasks) error = %v", err)
	}
	if importResult.TasksImported != 2 {
		t.Fatalf("TasksImported=%d, want 2; errors=%v", importResult.TasksImported, importResult.Errors)
	}
	importedChildren, importedTotal, err := models.ListTasks(parent.MemberID, models.TaskFilter{Keyword: "导入子待办", Page: 1, PageSize: 20})
	if err != nil {
		t.Fatalf("ListTasks(imported child) error = %v", err)
	}
	if importedTotal != 1 || len(importedChildren) != 1 || importedChildren[0].ParentID == 0 {
		t.Fatalf("imported child total=%d tasks=%v, want child with parent", importedTotal, importedChildren)
	}

	w = adminAssetRequest(router, token, http.MethodPut, "/api/tasks/"+itoa(parentResp.Data.TaskID), map[string]any{
		"content":   "重新设计待办模型",
		"due_date":  "2026-06-12",
		"parent_id": childResp.Data.TaskID,
	})
	if w.Code != http.StatusBadRequest {
		t.Fatalf("PUT cyclic parent status = %d, body=%s", w.Code, w.Body.String())
	}

	w = adminAssetRequest(router, token, http.MethodDelete, "/api/tasks/"+itoa(parentResp.Data.TaskID), nil)
	if w.Code != http.StatusOK {
		t.Fatalf("DELETE /api/tasks/:id status = %d, body=%s", w.Code, w.Body.String())
	}
	if _, err := models.GetTaskByID(childResp.Data.TaskID); err == nil {
		t.Fatalf("child should be deleted with parent")
	}
	trashItems, trashTotal, err := models.ListTrash(parent.MemberID, "task", 1, 20)
	if err != nil {
		t.Fatalf("ListTrash(task) error = %v", err)
	}
	if trashTotal != 1 || len(trashItems) != 1 || trashItems[0].ResourceName != "重新设计待办模型" {
		t.Fatalf("task trash total=%d items=%v, want deleted parent", trashTotal, trashItems)
	}
	if err := models.RestoreFromTrash(trashItems[0].TrashID); err != nil {
		t.Fatalf("RestoreFromTrash(task) error = %v", err)
	}
	restoredChild, err := models.GetTaskByID(childResp.Data.TaskID)
	if err != nil {
		t.Fatalf("restored child GetTaskByID error = %v", err)
	}
	if restoredChild.ParentID != parentResp.Data.TaskID {
		t.Fatalf("restored child parent_id=%d, want %d", restoredChild.ParentID, parentResp.Data.TaskID)
	}
}

type taskResponse struct {
	Code int `json:"code"`
	Data struct {
		TaskID   int64  `json:"task_id"`
		Content  string `json:"content"`
		DueDate  string `json:"due_date"`
		Done     bool   `json:"done"`
		ParentID int64  `json:"parent_id"`
	} `json:"data"`
}

func boolPtr(v bool) *bool {
	return &v
}

func itoa(id int64) string {
	return strconv.FormatInt(id, 10)
}
