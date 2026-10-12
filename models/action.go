package models

import (
	"fmt"
	"strings"
	"time"
)

type Task struct {
	TaskID       int64      `json:"task_id"`
	Content      string     `json:"content"`
	DueDate      string     `json:"due_date"`
	Done         bool       `json:"done"`
	ParentID     int64      `json:"parent_id"`
	TopicID      int64      `json:"topic_id"`
	ChildTotal   int        `json:"child_total"`
	ChildDone    int        `json:"child_done"`
	Children     []Task     `json:"children,omitempty"`
	CommentCount int        `json:"comment_count"`
	MemberID     int64      `json:"member_id"`
	CompleteTime *time.Time `json:"complete_time"`
	CreateTime   time.Time  `json:"create_time"`
	ModifyTime   time.Time  `json:"modify_time"`
}

type TaskFilter struct {
	Keyword         string
	Done            *bool
	ParentID        int64
	ParentSet       bool
	TopicID         int64
	DueBefore       string
	DueAfter        string
	DueOn           string
	ModifiedDate    string
	IncludeChildren bool
	Page            int
	PageSize        int
}

type TaskDailyCount struct {
	Date        string `json:"date"`
	Count       int    `json:"count"`
	DoneCount   int    `json:"done_count"`
	ActiveCount int    `json:"active_count"`
}

func ListTasks(memberID int64, f TaskFilter) ([]Task, int64, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.PageSize < 1 {
		f.PageSize = 30
	}
	if f.PageSize > 100 {
		f.PageSize = 100
	}

	where, args := taskWhere(memberID, f)
	whereSQL := "WHERE " + strings.Join(where, " AND ")
	var total int64
	if err := DB.QueryRow("SELECT COUNT(*) FROM md_tasks t "+whereSQL, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := `
		SELECT t.task_id, t.content, t.due_date, t.done, t.parent_id,
			(SELECT COUNT(*) FROM md_tasks c WHERE c.parent_id = t.task_id AND c.member_id = t.member_id) AS child_total,
			(SELECT COUNT(*) FROM md_tasks c WHERE c.parent_id = t.task_id AND c.member_id = t.member_id AND c.done = 1) AS child_done,
			t.topic_id, t.member_id, t.complete_time, t.create_time, t.modify_time
		FROM md_tasks t
		` + whereSQL + `
		ORDER BY t.done ASC,
			CASE WHEN t.due_date = '' THEN 1 ELSE 0 END,
			t.due_date ASC,
			t.modify_time DESC
		LIMIT ? OFFSET ?`
	dataArgs := append(args, f.PageSize, (f.Page-1)*f.PageSize)
	rows, err := DB.Query(query, dataArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	tasks, err := scanTasks(rows)
	if err != nil {
		return nil, 0, err
	}
	if f.IncludeChildren {
		if err := attachChildren(memberID, tasks); err != nil {
			return nil, 0, err
		}
	}
	return tasks, total, nil
}

func taskWhere(memberID int64, f TaskFilter) ([]string, []interface{}) {
	where := []string{"t.member_id = ?"}
	args := []interface{}{memberID}
	if f.Keyword != "" {
		where = append(where, "t.content LIKE ?")
		args = append(args, "%"+f.Keyword+"%")
	}
	if f.Done != nil {
		where = append(where, "t.done = ?")
		args = append(args, boolToInt(*f.Done))
	}
	if f.ParentSet {
		where = append(where, "t.parent_id = ?")
		args = append(args, f.ParentID)
	}
	if f.TopicID > 0 {
		where = append(where, "t.topic_id = ?")
		args = append(args, f.TopicID)
	}
	if f.DueBefore != "" {
		where = append(where, "t.due_date != '' AND t.due_date <= ?")
		args = append(args, f.DueBefore)
	}
	if f.DueAfter != "" {
		where = append(where, "(t.due_date = '' OR t.due_date > ?)")
		args = append(args, f.DueAfter)
	}
	if f.DueOn != "" {
		where = append(where, "t.due_date = ?")
		args = append(args, f.DueOn)
	}
	if f.ModifiedDate != "" {
		where = append(where, "substr(t.modify_time, 1, 10) = ?")
		args = append(args, f.ModifiedDate)
	}
	return where, args
}

type taskScanner interface {
	Scan(dest ...interface{}) error
}

type rowsScanner interface {
	Next() bool
	Err() error
	Scan(dest ...interface{}) error
}

func scanTask(row taskScanner) (*Task, error) {
	var t Task
	var done int
	err := row.Scan(&t.TaskID, &t.Content, &t.DueDate, &done, &t.ParentID, &t.ChildTotal, &t.ChildDone, &t.TopicID, &t.MemberID, &t.CompleteTime, &t.CreateTime, &t.ModifyTime)
	if err != nil {
		return nil, err
	}
	t.Done = done == 1
	return &t, nil
}

func scanTasks(rows rowsScanner) ([]Task, error) {
	var tasks []Task
	for rows.Next() {
		t, err := scanTask(rows)
		if err != nil {
			return nil, err
		}
		tasks = append(tasks, *t)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if tasks == nil {
		tasks = []Task{}
	}
	return tasks, nil
}

func attachChildren(memberID int64, tasks []Task) error {
	for i := range tasks {
		children, _, err := ListTasks(memberID, TaskFilter{ParentID: tasks[i].TaskID, ParentSet: true, IncludeChildren: true, Page: 1, PageSize: 100})
		if err != nil {
			return err
		}
		tasks[i].Children = children
	}
	return nil
}

func GetTaskByID(id int64) (*Task, error) {
	return getTaskByID(id)
}

func getTaskByID(id int64) (*Task, error) {
	return scanTask(DB.QueryRow(`
		SELECT task_id, content, due_date, done, parent_id,
			(SELECT COUNT(*) FROM md_tasks c WHERE c.parent_id = md_tasks.task_id AND c.member_id = md_tasks.member_id) AS child_total,
			(SELECT COUNT(*) FROM md_tasks c WHERE c.parent_id = md_tasks.task_id AND c.member_id = md_tasks.member_id AND c.done = 1) AS child_done,
			topic_id, member_id, complete_time, create_time, modify_time
		FROM md_tasks WHERE task_id = ?`, id))
}

func IsTaskDescendant(taskID, candidateID, memberID int64) (bool, error) {
	var count int
	err := DB.QueryRow(`
		WITH RECURSIVE descendants(task_id) AS (
			SELECT task_id FROM md_tasks WHERE parent_id = ? AND member_id = ?
			UNION ALL
			SELECT child.task_id
			FROM md_tasks child
			JOIN descendants parent ON child.parent_id = parent.task_id
			WHERE child.member_id = ?
		)
		SELECT COUNT(*) FROM descendants WHERE task_id = ?`,
		taskID, memberID, memberID, candidateID).Scan(&count)
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

func CreateTask(t *Task) error {
	return createTaskWith(DB, t)
}

func createTaskWith(db sqlExecutor, t *Task) error {
	now := time.Now()
	t.CreateTime = now
	t.ModifyTime = now
	if t.Done && t.CompleteTime == nil {
		t.CompleteTime = &now
	}
	if !t.Done {
		t.CompleteTime = nil
	}
	res, err := db.Exec(`
		INSERT INTO md_tasks (content, due_date, done, parent_id, topic_id, member_id, complete_time, create_time, modify_time)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		t.Content, t.DueDate, boolToInt(t.Done), t.ParentID, t.TopicID, t.MemberID, t.CompleteTime, t.CreateTime, t.ModifyTime)
	if err != nil {
		return err
	}
	t.TaskID, _ = res.LastInsertId()
	return nil
}

func UpdateTask(t *Task) error {
	now := time.Now()
	t.ModifyTime = now
	if t.Done && t.CompleteTime == nil {
		t.CompleteTime = &now
	}
	if !t.Done {
		t.CompleteTime = nil
	}
	res, err := DB.Exec(`
		UPDATE md_tasks
		SET content = ?, due_date = ?, done = ?, parent_id = ?, topic_id = ?, complete_time = ?, modify_time = ?
		WHERE task_id = ?`,
		t.Content, t.DueDate, boolToInt(t.Done), t.ParentID, t.TopicID, t.CompleteTime, t.ModifyTime, t.TaskID)
	if err != nil {
		return err
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return fmt.Errorf("待办不存在")
	}
	return nil
}

func UpdateTaskDone(id int64, done bool) error {
	now := time.Now()
	var complete interface{}
	if done {
		complete = now
	}
	res, err := DB.Exec("UPDATE md_tasks SET done = ?, complete_time = ?, modify_time = ? WHERE task_id = ?", boolToInt(done), complete, now, id)
	if err != nil {
		return err
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return fmt.Errorf("待办不存在")
	}
	return nil
}

func DeleteTask(id int64) error {
	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	snap, name, err := SnapshotTask(tx, id)
	if err != nil {
		return err
	}
	if snap.Task == nil {
		return fmt.Errorf("待办不存在")
	}
	if snap.Task.TopicID > 0 {
		if _, err := tx.Exec(`
			WITH RECURSIVE subtree(task_id) AS (
				SELECT task_id FROM md_tasks WHERE task_id = ?
				UNION ALL
				SELECT child.task_id
				FROM md_tasks child
				JOIN subtree parent ON child.parent_id = parent.task_id
			)
			DELETE FROM md_topic_comments
			WHERE topic_id = ? AND target_type = ? AND target_id IN (SELECT task_id FROM subtree)`,
			id, snap.Task.TopicID, TopicCommentTask); err != nil {
			return err
		}
	}
	res, err := tx.Exec(`
		WITH RECURSIVE subtree(task_id) AS (
			SELECT task_id FROM md_tasks WHERE task_id = ?
			UNION ALL
			SELECT child.task_id
			FROM md_tasks child
			JOIN subtree parent ON child.parent_id = parent.task_id
		)
		DELETE FROM md_tasks WHERE task_id IN (SELECT task_id FROM subtree)`, id)
	if err != nil {
		return err
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return fmt.Errorf("待办不存在")
	}
	if err := CreateTrash(tx, "task", name, snap, snap.Task.MemberID); err != nil {
		return err
	}
	return tx.Commit()
}

func GetTaskDailyCounts(memberID int64, year, month int) ([]TaskDailyCount, error) {
	startDate := fmt.Sprintf("%04d-%02d-01", year, month)
	endDate := fmt.Sprintf("%04d-%02d-31", year, month)
	rows, err := DB.Query(`
		SELECT substr(modify_time, 1, 10) AS d,
			COUNT(*) AS cnt,
			SUM(CASE WHEN done = 1 THEN 1 ELSE 0 END) AS done_count,
			SUM(CASE WHEN done = 0 THEN 1 ELSE 0 END) AS active_count
		FROM md_tasks
		WHERE member_id = ? AND substr(modify_time, 1, 10) BETWEEN ? AND ?
		GROUP BY d
		ORDER BY d`, memberID, startDate, endDate)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []TaskDailyCount
	for rows.Next() {
		var r TaskDailyCount
		if err := rows.Scan(&r.Date, &r.Count, &r.DoneCount, &r.ActiveCount); err != nil {
			return nil, err
		}
		result = append(result, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if result == nil {
		result = []TaskDailyCount{}
	}
	return result, nil
}

func boolToInt(v bool) int {
	if v {
		return 1
	}
	return 0
}
