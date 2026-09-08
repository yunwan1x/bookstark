package main

import (
	"database/sql"
	"fmt"
	"log"
	"math/rand"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

var bookAdjectives = []string{
	"深入理解", "精通", "从零开始", "高级", "实战", "进阶", "图解", "手把手教你",
	"一本通", "权威指南", "设计模式", "性能优化", "架构设计", "最佳实践", "核心原理",
}

var bookTopics = []string{
	"Go语言", "Python编程", "Rust系统编程", "JavaScript全栈", "TypeScript",
	"React框架", "Vue.js", "Kubernetes", "Docker容器", "微服务架构",
	"分布式系统", "数据库原理", "Redis缓存", "消息队列", "Kafka",
	"机器学习", "深度学习", "自然语言处理", "计算机视觉", "推荐系统",
	"Linux内核", "网络协议", "编译原理", "操作系统", "算法与数据结构",
	"云原生", "Serverless", "GraphQL", "gRPC", "WebAssembly",
	"区块链", "智能合约", "DevOps", "CI/CD", "监控与告警",
	"安全攻防", "密码学", "前端工程化", "后端架构", "数据治理",
}

var blogTitles = []string{
	"如何优雅地处理", "深入浅出", "一文搞懂", "踩坑记录：", "实战分享：",
	"从原理到实践：", "性能调优：", "最佳方案：", "架构思考：", "技术选型：",
	"团队实践：", "经验总结：", "源码分析：", "原理剖析：", "方案对比：",
}

var blogSuffixes = []string{
	"Go并发编程", "React Hooks", "K8s部署策略", "MySQL索引优化", "Redis持久化",
	"微服务拆分", "API设计", "日志系统", "监控体系", "灰度发布",
	"容器网络", "服务网格", "配置中心", "链路追踪", "限流降级",
	"数据迁移", "缓存穿透", "消息幂等", "分库分表", "读写分离",
	"单元测试", "集成测试", "压力测试", "A/B测试", "混沌工程",
	"代码审查", "技术债务", "重构策略", "设计评审", "故障复盘",
	"Golang GC调优", "Node.js事件循环", "JVM内存模型", "Python异步IO", "Rust所有权",
	"WebSocket实战", "SSE推送", "长轮询优化", "CDN加速", "边缘计算",
}

var labels = []string{
	"Go", "Python", "Rust", "JavaScript", "TypeScript",
	"React", "Vue", "Kubernetes", "Docker", "微服务",
	"数据库", "Redis", "Kafka", "机器学习", "DevOps",
	"前端", "后端", "架构", "算法", "安全",
	"云原生", "Linux", "网络", "性能优化", "最佳实践",
}

var markdownTemplates = []string{
	"# %s\n\n## 概述\n\n本文介绍了%s的核心概念和实践方法。\n\n## 背景\n\n在日常开发中，我们经常会遇到各种挑战。本文将从实际项目出发，分享一些经验。\n\n## 详细内容\n\n### 第一部分\n\n这是一个很重要的概念。在实际应用中，我们需要注意以下几点：\n\n1. 理解基本原理\n2. 掌握核心API\n3. 熟悉最佳实践\n\n### 第二部分\n\n```go\npackage main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"Hello, World!\")\n}\n```\n\n## 总结\n\n通过本文的学习，我们掌握了%s的基本用法。",
	"# %s\n\n> 本文是系列文章的一部分。\n\n## 问题描述\n\n在%s的过程中，经常会遇到一些棘手的问题。\n\n## 解决方案\n\n经过调研和实验，我们找到了一种优雅的解决方案：\n\n- 方案一：适用于小规模场景\n- 方案二：适用于大规模分布式场景\n- 方案三：折中方案\n\n## 性能对比\n\n| 方案 | QPS | 延迟 | 内存 |\n|------|-----|------|------|\n| 方案一 | 10K | 5ms | 100MB |\n| 方案二 | 50K | 2ms | 500MB |\n| 方案三 | 30K | 3ms | 200MB |\n\n## 结论\n\n%s是一个值得深入学习的领域。",
}

func main() {
	db, err := sql.Open("sqlite", "./bookstark.db")
	if err != nil {
		log.Fatalf("打开数据库失败: %v", err)
	}
	defer db.Close()

	db.Exec("PRAGMA journal_mode=WAL")
	db.Exec("PRAGMA foreign_keys=ON")

	var memberID int64
	err = db.QueryRow("SELECT member_id FROM md_members WHERE role = 0 LIMIT 1").Scan(&memberID)
	if err != nil {
		log.Fatalf("找不到管理员用户: %v", err)
	}
	fmt.Printf("使用管理员 member_id=%d\n", memberID)

	// 插入标签
	fmt.Println("插入标签...")
	labelIDs := make(map[string]int64)
	for _, l := range labels {
		res, err := db.Exec("INSERT OR IGNORE INTO md_label (label_name) VALUES (?)", l)
		if err != nil {
			log.Printf("插入标签 %s 失败: %v", l, err)
			continue
		}
		id, _ := res.LastInsertId()
		if id == 0 {
			db.QueryRow("SELECT label_id FROM md_label WHERE label_name = ?", l).Scan(&id)
		}
		labelIDs[l] = id
	}

	// 插入书籍
	fmt.Println("插入 1000 本书籍...")
	tx, _ := db.Begin()
	bookIDs := make([]int64, 0, 1000)
	baseTime := time.Date(2024, 1, 1, 0, 0, 0, 0, time.Local)

	for i := 0; i < 1000; i++ {
		adj := bookAdjectives[rand.Intn(len(bookAdjectives))]
		topic := bookTopics[rand.Intn(len(bookTopics))]
		name := fmt.Sprintf("%s%s", adj, topic)
		identify := fmt.Sprintf("book-%d-%d", time.Now().UnixNano(), i)
		desc := fmt.Sprintf("这是一本关于%s的技术书籍，涵盖了从入门到精通的完整内容。", topic)

		// 随机选 1-3 个标签
		numLabels := rand.Intn(3) + 1
		bookLabels := make([]string, 0, numLabels)
		for j := 0; j < numLabels; j++ {
			bookLabels = append(bookLabels, labels[rand.Intn(len(labels))])
		}
		labelStr := strings.Join(bookLabels, ",")

		createTime := baseTime.Add(time.Duration(rand.Intn(365*2*24)) * time.Hour)
		docCount := rand.Intn(20) + 1

		res, err := tx.Exec(
			`INSERT INTO md_books (book_name, identify, description, label, doc_count, member_id, create_time, modify_time)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			name, identify, desc, labelStr, docCount, memberID, createTime, createTime,
		)
		if err != nil {
			log.Printf("插入书籍 %d 失败: %v", i, err)
			continue
		}
		bookID, _ := res.LastInsertId()
		bookIDs = append(bookIDs, bookID)

		// 为每本书创建一些文档
		numDocs := rand.Intn(5) + 1
		for d := 0; d < numDocs; d++ {
			docName := fmt.Sprintf("第%d章 %s", d+1, topic)
			docIdentify := fmt.Sprintf("doc-%d-%d-%d", bookID, d, time.Now().UnixNano())
			tmpl := markdownTemplates[rand.Intn(len(markdownTemplates))]
			content := fmt.Sprintf(tmpl, docName, topic, topic)

			tx.Exec(
				`INSERT INTO md_documents (document_name, identify, book_id, parent_id, order_sort, markdown, member_id, create_time, modify_time)
				 VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?)`,
				docName, docIdentify, bookID, d, content, memberID, createTime, createTime,
			)
		}

		// 关联标签
		for _, l := range bookLabels {
			if lid, ok := labelIDs[l]; ok {
				tx.Exec("INSERT OR IGNORE INTO md_label_relation (label_id, resource_id, relation_type, created_at) VALUES (?, ?, 'book', datetime('now'))", lid, bookID)
			}
		}
	}
	tx.Commit()
	fmt.Printf("  完成，共 %d 本书籍\n", len(bookIDs))

	// 插入博客
	fmt.Println("插入 1000 篇博客...")
	tx, _ = db.Begin()
	blogIDs := make([]int64, 0, 1000)

	for i := 0; i < 1000; i++ {
		prefix := blogTitles[rand.Intn(len(blogTitles))]
		suffix := blogSuffixes[rand.Intn(len(blogSuffixes))]
		title := prefix + suffix
		identify := fmt.Sprintf("blog-%d-%d", time.Now().UnixNano(), i)

		tmpl := markdownTemplates[rand.Intn(len(markdownTemplates))]
		content := fmt.Sprintf(tmpl, title, suffix, suffix)

		createTime := baseTime.Add(time.Duration(rand.Intn(365*2*24)) * time.Hour)

		res, err := tx.Exec(
			`INSERT INTO md_blogs (blog_title, blog_identify, member_id, blog_content, password, modify_time, create_time, version)
			 VALUES (?, ?, ?, ?, '', ?, ?, 1)`,
			title, identify, memberID, content, createTime, createTime,
		)
		if err != nil {
			log.Printf("插入博客 %d 失败: %v", i, err)
			continue
		}
		blogID, _ := res.LastInsertId()
		blogIDs = append(blogIDs, blogID)

		// 关联 1-3 个标签
		numLabels := rand.Intn(3) + 1
		for j := 0; j < numLabels; j++ {
			l := labels[rand.Intn(len(labels))]
			if lid, ok := labelIDs[l]; ok {
				tx.Exec("INSERT OR IGNORE INTO md_label_relation (label_id, resource_id, relation_type, created_at) VALUES (?, ?, 'blog', datetime('now'))", lid, blogID)
			}
		}
	}
	tx.Commit()
	fmt.Printf("  完成，共 %d 篇博客\n", len(blogIDs))

	// 插入分享（50个博客分享 + 50个文档分享）
	fmt.Println("插入 100 个分享...")
	tx, _ = db.Begin()
	shareCount := 0

	// 分享50个博客
	usedBlogs := make(map[int64]bool)
	for shareCount < 50 && len(usedBlogs) < len(blogIDs) {
		blogID := blogIDs[rand.Intn(len(blogIDs))]
		if usedBlogs[blogID] {
			continue
		}
		usedBlogs[blogID] = true
		identify := fmt.Sprintf("share-%d-%d", time.Now().UnixNano(), shareCount)
		shareTime := baseTime.Add(time.Duration(rand.Intn(365*2*24)) * time.Hour)
		_, err := tx.Exec(
			"INSERT OR IGNORE INTO md_shares (share_type, share_identify, target_id, member_id, share_time) VALUES ('blog', ?, ?, ?, ?)",
			identify, blogID, memberID, shareTime,
		)
		if err == nil {
			shareCount++
		}
	}

	// 分享50个文档
	var docIDs []int64
	rows, err := db.Query("SELECT document_id FROM md_documents LIMIT 500")
	if err == nil {
		for rows.Next() {
			var id int64
			rows.Scan(&id)
			docIDs = append(docIDs, id)
		}
		rows.Close()
	}

	usedDocs := make(map[int64]bool)
	for shareCount < 100 && len(usedDocs) < len(docIDs) {
		docID := docIDs[rand.Intn(len(docIDs))]
		if usedDocs[docID] {
			continue
		}
		usedDocs[docID] = true
		identify := fmt.Sprintf("share-%d-%d", time.Now().UnixNano(), shareCount)
		shareTime := baseTime.Add(time.Duration(rand.Intn(365*2*24)) * time.Hour)
		_, err := tx.Exec(
			"INSERT OR IGNORE INTO md_shares (share_type, share_identify, target_id, member_id, share_time) VALUES ('document', ?, ?, ?, ?)",
			identify, docID, memberID, shareTime,
		)
		if err == nil {
			shareCount++
		}
	}
	tx.Commit()
	fmt.Printf("  完成，共 %d 个分享\n", shareCount)

	// 统计
	var bookTotal, blogTotal, shareTotal, docTotal, labelTotal int64
	db.QueryRow("SELECT COUNT(*) FROM md_books").Scan(&bookTotal)
	db.QueryRow("SELECT COUNT(*) FROM md_blogs").Scan(&blogTotal)
	db.QueryRow("SELECT COUNT(*) FROM md_shares").Scan(&shareTotal)
	db.QueryRow("SELECT COUNT(*) FROM md_documents").Scan(&docTotal)
	db.QueryRow("SELECT COUNT(*) FROM md_label").Scan(&labelTotal)

	fmt.Printf("\n=== 数据库统计 ===\n")
	fmt.Printf("书籍: %d\n", bookTotal)
	fmt.Printf("文档: %d\n", docTotal)
	fmt.Printf("博客: %d\n", blogTotal)
	fmt.Printf("分享: %d\n", shareTotal)
	fmt.Printf("标签: %d\n", labelTotal)
	fmt.Println("Mock 数据插入完成！")
}
