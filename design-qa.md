# 待整理首页、日历与提醒检查

日期：2026-10-27。版本 1.1，构建 11。

首页只显示最近一个未完成日期的剩余图片；照片、截图使用分区卡片，单张图片横排，完成内容与空分类隐藏。底栏按用户参考保留上一版圆环、状态、日期和右侧继续整理；今日已完成时勾选状态保留，实际内容切到历史未整理任务。

日历通过数量和状态图例展示每日进度，可对任一天重新整理。操作固定在面板底部，不需要滚到底才能找到。我的提供整理提醒开关与时间，默认 22:00，系统拒绝通知时可以前往设置。

全部照片筛选使用独立分区面板，照片类型、月份与重新整理分开显示，替代层层展开的菜单。

已人工查看实际 iPhone/iPad 导出截图，未修改原图：

- `.ui-checks/inbox-reminder/iphone-footer-shots/pending-older-day-home.png`
- `.ui-checks/inbox-reminder/iphone-footer-shots/daily-inbox.png`
- `.ui-checks/inbox-reminder/iphone-polish-shots/sorting-reminder-enabled.png`
- `.ui-checks/inbox-reminder/ipad-polish-shots/calendar-restart-day.png`

53 项单元测试通过；手机和 iPad 的提醒、重整日期、隐藏完成内容、历史接续及底栏恢复分别完成针对性回归。逐次测试结果、初期失败原因与真机投递边界见 VALIDATION.md 和本机 `.ui-checks/inbox-reminder/QA.md`。

本轮没有自动删除真机照片或发布 App Store。实际夜间通知投递、大库性能和 iCloud 下载不以模拟器结果替代。

最终筛选面板与统一背景月份列表在 iPhone/iPad 各完成 1 项流程回归；已检查原始截图 `iphone-filter-shots/filter-panel.png` 和 `ipad-filter-shots/filter-panel.png`。最终版本 1.1（11）已安装到同一手机，最终构建、回归与回执见 VALIDATION.md。

final result: passed
