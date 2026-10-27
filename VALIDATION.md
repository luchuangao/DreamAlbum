# 梦想相册重构验证记录

日期：2026-10-23。代码目标为原生 iOS / iPadOS App，与 `Design/selected-dark-photo-album.png` 对齐，不包含 App Store 发布。

## 已验证

| 项目 | 证据与范围 |
| --- | --- |
| iOS / iPadOS 编译 | Xcode 26.5，iOS Simulator，iOS 17 部署目标；共享 DreamAlbum Scheme 含 App、Widget、单元与界面测试 |
| iPhone 最终回归 | `/tmp/dream-photo-iphone-releasecheck.xcresult`：15 项单元测试、2 项界面测试通过；iPhone 17 Pro，iOS 26.5；包括实际左右滑动 |
| iPad 完整流程 | `/tmp/dream-photo-ipad-07.xcresult`：15 项单元测试、2 项界面测试通过；iPad Pro 11-inch (M5)，iPadOS 26.5 |
| Mac Catalyst 编译 | `/tmp/dream-photo-mac-final.log`，arm64，`BUILD SUCCEEDED`；未签名本地构建 |
| 整理状态 | 队列去重、左右操作对应的判断、连续撤销、保存恢复、新一轮保留待删清单、清空/取消不可被撤销意外恢复 |
| 删除状态 | 标记不调用系统删除；模拟服务删除失败保留队列，成功才移除；外部删除后清理失效标识；界面取消确认保留原图 |
| 权限边界 | 模拟服务覆盖拒绝、有限授权、完整授权，以及查询中升级授权时不能将有限快照当完整快照清理队列 |
| 系统分组与画册导入 | 模拟器真实 PhotoKit 创建相册、加入照片，再保存独立副本创建梦想画册；目标照片实际来自模拟器照片库 |
| 导入失败与取消 | 模拟服务失败重试、关闭后清理临时副本；提交后清理原图，画册副本仍存在并能解码 |
| 旧数据 | 缺少较新可选字段的 Dream JSON 解码与往返编码；旧图片路径原样保留 |
| 万张元数据 | 10,000 个标识的状态机和 Store 测试，确认元数据载入不请求图像；这不等于真机万张照片库的内存/滚动实测 |
| 视觉与操作栏 | 见 `design-qa.md` 及 `.ui-checks/photo-refactor/`；iPad 多选操作栏与底部导航分区显示，已验证导入入口可用 |

单元测试使用隔离的 UserDefaults suite；独立画册提交测试会在测试模拟器暂时创建画册并恢复原数据。界面测试在测试模拟器创建测试相册及画册，不执行实际原图删除。现有成长记录、里程碑、组件和 iCloud 数据格式沿用原实现，没有清空或重新编号。

Mac 链接器会提示本机 Metal toolchain 的一个 Swift 搜索目录不存在，构建成功；该提示不是照片服务编译错误。

## 仍需真机/外部状态验证

开发阶段 iPhone 曾被 Xcode 列为 Offline。后续通过 CoreDevice 确认手机已通过数据线配对连接、开发者模式开启，并已完成下述真机安装。以下功能验收仍未声称完成：

- 首次授权、有限照片选择器、限制/撤销权限，及在苹果照片 App 修改后回到本 App 的更新。
- 仅用专门测试照片验证系统删除确认、取消、成功后的照片库变化；确认独立画册副本保留。Live Photo 应同时删除其静态与动态资源。
- 系统相册重命名、重复加入、移出和删除相册，确认原图保留；智能相册只读，共享相册不进入编辑流程。
- iCloud 优化存储照片的实际下载、断网、恢复网络与取消；空间不足时失败提示和临时文件清理。
- 两台设备的系统 iCloud 照片同步，以及既有 App iCloud 备份恢复、归档、成长记录和 Widget 回归。
- 真机万张照片库连续滚动、连续整理时的峰值内存与响应，以及 VoiceOver、较大字号、外接键盘。

这些是设备验收缺口，不以模拟服务或编译结果代替。连接已信任的 iPhone 后，先使用测试照片完成上述检查，再考虑发布。

## 重复验证

编译及单元测试命令见 README。界面测试需要已启动的测试模拟器、至少两张图片以及完整照片授权；测试可通过 `-only-testing:DreamAlbumUITests` 单独运行。重新安装二进制可能重置模拟器授权，需要在安装后重新允许访问。

`.xcresult` 和 `/tmp` 日志属于本机验证输出；交付截图与本记录留在项目内。由于初始磁盘空间不足，失败的临时结果和本次编译缓存已做定向清理，未清理历史构建目录或用户照片。

## 真机安装记录

2026-10-23：在用户明确要求“安装到手机上”后，使用项目现有开发团队自动签名，真机 Debug 构建通过。通过 `devicectl device install app` 覆盖更新 iPhone 15（iOS 27.0.1）上的 `com.luchuangao.mengxiangxiangce`，没有卸载旧 App。随后 `devicectl device process launch` 成功启动新版。

安装包：`.DerivedDataPhotoDevice/Build/Products/Debug-iphoneos/DreamAlbum.app`；安装、启动结构化记录保存在 `.ui-checks/photo-refactor/results/device-install.json` 和 `device-launch.json`。本次安装不自动操作或删除手机照片，也不等于完成以上全部真机功能验收。

## 2026-10-24 统一背景与原生选图优化

版本 1.1（构建 5）：统一四个主页面、画册详情、编辑表单和分享预览底色；保留旧背景数据字段兼容。照片网格改用 UICollectionView，支持单击选择/取消、长按进入选择、横向范围选择和系统双指多选；选中数量、全选/取消全选更明确。进入选择不重排照片。预览改用 UIScrollView，支持捏合、双击与放大后平移。

- iPhone：`.ui-checks/ux-polish/iphone-final.xcresult` 的 18 项单元与 4 项 UI 测试通过；后续封面命中修复与海报检查由 `iphone-polished.xcresult` 两项 UI 测试再次通过。
- iPad：`ipad-final.xcresult` 的 18 项单元、多选/预览、英文界面和整理/分组/画册导入流程通过。外观检查曾发现封面点击区域超出卡片的问题；显式限制 contentShape 并合并辅助功能标签后，`ipad-appearance.xcresult` 该项复查通过。
- 真机 Debug 自动签名构建及 Mac Catalyst 编译通过，日志在 `.ui-checks/ux-polish/build-device.log`、`build-mac.log`。最后的分享预览颜色微调完成编译，未重复全套 UI 测试。
- 照片选择范围计算增加 3 项单元测试，覆盖增选、取消、反向缩小范围和过期索引；选中状态改变不重新发起缩略图请求。
- 截图与步骤记录：`.ui-checks/ux-polish/UX-REVIEW.md`、`after-iphone/`、`after-ipad/`。

通过 devicectl 使用设备 UDID 覆盖更新已配对 iPhone 15 上的 `com.luchuangao.mengxiangxiangce`，安装回执为 `.ui-checks/ux-polish/device-install.json`。首次以 CoreDevice UUID 连接失败，改用同一手机的 UDID 后成功。未卸载、清空数据或执行原图删除。此前列出的真机权限、iCloud、系统双指手势、触觉反馈和万张库性能验收边界仍适用。

测试期间磁盘空间不足，仅定向清理本次创建的失败测试结果及三个 Photo 构建目录的 Xcode 索引缓存；未清理用户照片与历史构建目录。

安装后的自动启动被手机锁屏状态阻止（`device-launch.json` 中为 `Locked`）；这不影响已经成功的覆盖安装。需用户解锁后从桌面打开，未声称已完成本次真机启动和交互验收。

## 2026-10-26 当天整理首页（构建 6）

按选定第 3 张 `Design/selected-daily-inbox.png` 实现：启动首页展示当天“随手拍”和“屏幕截图”，可直接分类整理或继续当天剩余内容；全部照片、月份和截图筛选保留在次级入口，移除旧的继续上次弹窗。按设备本地时区使用 Calendar 计算日期边界，日期未知图片仍在全部照片。跨分类、日期和重新启动保留判断与待删标记；手动重新整理仅重置指定范围。

- 24 项单元测试通过（`.ui-checks/daily-inbox/iphone.xcresult`），新增 6 项覆盖日期/夏令时、空/完成/新增内容、旧 JSON、跨范围续接、撤销与清理。
- iPhone：原有 5 项 UI 场景通过；新首页首次检查发现分类按钮语义和日期面板高度问题，修复后 `iphone-daily-final.xcresult` 验证分类、数量、无弹窗续接、重启、日历和全部照片通过。
- iPad：`ipad.xcresult` 最终 6 项界面测试全部通过，包含新首页流程及原有整理、撤销、取消删除、系统分组、独立画册导入、原生多选、预览和英文导航。
- Mac Catalyst 与真机 Debug 构建通过，日志在 `.ui-checks/daily-inbox/build-mac.log`、`build-device.log`。
- 主界面测试服务使用独立 UserDefaults，只在 Debug 且显式传入 `-dailyInboxFixture` 时启用；实际启动没有测试参数，继续使用系统照片库。Release 编译不包含测试服务。
- 视觉报告为根目录 `design-qa.md`；截图为 `.ui-checks/daily-inbox/iphone-final-shots/` 与 `ipad-shots/`。

以上验证未进行真实手机原图删除，真机权限、云端下载、万张库性能等边界仍沿用前面的验收记录。

构建 6 已通过 devicectl 覆盖安装到用户的 iPhone 15（同一 bundle ID，无卸载、无清空数据），回执见 `.ui-checks/daily-inbox/device-install.json`。自动启动被手机锁屏状态阻止，见 `device-launch.json`；需解锁后手动打开，不将安装成功误记为真机交互验收。

## 2026-10-26 日历计数、分组操作与简洁文案（构建 7）

- 日历采用月视图元数据索引，显示每日图片数；含照片与截图，排除日期未知图片，按本机 Calendar / 时区统计。月切换、快速日期跳转、当天高亮与未来日期禁用均保留。
- 分组增加可见的“更多”菜单、左滑与长按操作。按 PhotoKit 编辑能力显示重命名/删除；删除分组仅调用删除相册接口，不调用删除原图接口。
- 删除原图、分组、画册、记录与描述时，不再显示 App 自己的重复确认；原图操作继续调用 PhotoKit，保留系统要求的确认。取消或失败不清理待删标记。
- 简化首页空状态、日期/数量、分组、待删提示、画册描述、成长记录等中英文文案，不修改用户已保存的标题和正文。
- 29 项单元测试通过（`ipad-delete-fixed.xcresult`），新增月份计数、月首偏移、闰年、夏令时、删除请求次数、错误呈现归属以及 PhotoKit 取消保留状态测试。
- iPhone：初始完整 9 项 UI 测试中 8 项通过，删除失败提示场景发现呈现归属问题。改为当前待删页独立呈现错误后，两项直接删除界面测试通过（`iphone-delete-fixed.xcresult`）。
- iPad：计数日历、日期选择、分组重命名/删除保留原图、删除成功流程通过（`ipad.xcresult`）；失败提示修复后单独复查通过（`ipad-delete-fixed.xcresult`）。
- Mac Catalyst 与真机 Debug 构建通过，日志在 `.ui-checks/calendar-actions/build-mac-final.log`、`build-device.log`。
- 删除成功/失败场景使用隔离测试服务；实际 PhotoKit 回归只在模拟器创建测试分组和画册，不执行手机原图删除。系统取消的 PHPhotosError 代码从本机 SDK 验证，并由单元测试模拟覆盖。

本轮测试产物、用户提供的修改前截图及更新后的截图均在 `.ui-checks/calendar-actions/`。设备上的权限、原图删除系统提示和真实大库性能仍需实际使用验证，不以模拟服务测试替代。

构建 7 已覆盖安装到用户 iPhone 15，并通过 devicectl 成功启动；回执为 `.ui-checks/calendar-actions/device-install.json` 和 `device-launch.json`。未卸载 App、未清空数据，也未在手机上执行照片删除。

## 2026-10-26 待删、大图滑动与自动返回（构建 8）

首页与全部照片新增待删数量入口，多选直接标记。今天无内容时回退最近 7 天；过早图库以最新可访问日期结束该范围。分组可连同图片原件在单一 PhotoKit 事务中删除，取消和失败保留状态，有限授权下仅清理已成功删除的资源标识。

删除成功后待删页自动关闭，失败与取消不关闭。当前范围整理完后回照片首页，重置次级浏览路径，保留本地判断和待删。预览支持左右判断、双指缩放和放大后平移；分组导入改为完整页面，键盘可以收起。

- 单元测试扩至 36 项，覆盖最近范围、分组删除失败与有限权限，以及宽屏滑动/快速滑动/纵向误触。
- 完整 18 场景回归与修复后的定向验证组合，详细结果与早期失败原因见 `.ui-checks/pending-workflow/QA.md`；最终 iPhone/iPad 预览手势流程均通过。
- 最终 iOS、Mac Catalyst 和自动签名真机编译通过，日志为该目录的 `build-device-final-install.log`、`build-mac-final-install.log`。构建 8 已覆盖安装并成功启动到同一配对 iPhone 15，证据为 `device-install.json` 与 `device-launch.json`。
- 没有通过自动化删除手机或持久模拟器库的真实原图。此前真机权限、iCloud、万张图库及辅助功能验收边界继续适用。


## 2026-10-26–27 首页进度与原生返回（构建 9）

- 首页完成卡片、空分类隐藏、较早日期续接、日期未知图片兜底和已完成分类浏览已实现。日历根据当前可访问图片与本地判断记录计算每日状态，新增图片后恢复未完成状态。
- 系统/只读分组改为文字标记并提供说明，编辑操作仍遵循 PhotoKit 返回能力。系统相册中的图片可继续整理，不能修改相册名称和系统分类。
- 全部照片使用系统导航栏，移除重复大标题，支持整页/边缘右滑返回。多选期间临时停用原生返回手势，结束、离开或销毁页面时恢复。
- 整理卡片与预览增加跟手移动、短滑回弹、提交滑出；预览最多缓存下一张。提交即保存判断，动画完成后显示下一张，缩放期间拖动只平移。
- `iphone.xcresult` 和 `ipad.xcresult` 各通过 40 项单元与 7 项 UI；`iphone-final.xcresult` 和 `ipad-final.xcresult` 各通过 3 项完成状态、分类与英文界面测试。
- `iphone-gestures.xcresult` 通过 43 项单元与 8 项 UI；iPad 同批 43 项单元通过，早期 UI 中发现纵向滚动断言不适用于宽屏及全内容返回手势抢占多选的问题。修正断言并协调 iOS 26 独立的 content-pop 手势后，最终 `iphone-content-back.xcresult`、`ipad-content-back.xcresult` 各 3 项导航和选择回归全部通过。早期失败结果保留，未记为全通过。
- 最终自动签名 iOS 与 Mac Catalyst 编译成功：`build-device-content-back.log`、`build-mac-content-back.log`。截图已导出至同目录的 `*-navigation-shots` 与 `*-final-shots` 并人工查看手机单图完成首页、iPad 导航和多选布局。
- 版本 1.1（9）已通过 devicectl 覆盖安装到配对 iPhone 15，bundle ID 不变，无卸载和数据清空，回执 `device-install.json`。启动结果另见 `device-launch.json` / `device-launch.log`。

本轮没有自动删除真机原图。系统权限切换、iCloud 下载及万张照片库性能仍须真机专项验收，模拟服务和编译通过不替代这些检查。详细证据见 `.ui-checks/review-progress/QA.md`。

构建 9 的自动启动被手机锁屏阻止（`device-launch.json` 为 Locked），覆盖安装已成功。用户解锁后可从桌面打开；未将安装结果记为真机交互验收通过。


## 2026-10-27 待整理任务、提醒与筛选（构建 10–11）

首页选择最近一个未完成日期，隐藏已完成图片和空分类；当天处理完后接续更早日期，最后处理日期未知图片。新图片优先出现，整理记录继续按本机持久化。分类卡片最多显示三张缩略图，单张图片采用紧凑横排。按用户最终参考图恢复上一版底部圆环、完成/剩余状态、日期数量和右侧继续整理。

日期面板新增重新整理当天，只重置所选日期判断，保留待删标记和其他日期进度；回到今天与重新整理固定在底部安全区域。我的新增独立本地整理提醒，默认关闭，首次开启请求通知权限，默认每天 22:00，可修改时间；关闭取消对应通知，不影响旧梦想提醒。拒绝后提供通知设置入口，失败可重试。提醒配置不写入画册云备份，串行调度避免快速关闭后残留旧请求。

- 53 项单元测试通过（`.ui-checks/inbox-reminder/iphone-final.xcresult`），增加 4 项待整理任务模型测试及 6 项提醒测试。覆盖跳过完成日期、同日已整理成员隐藏、新照片优先、无日期、单日重新整理与待删保留，以及默认时间、权限拒绝/撤回、持久化、自定义时间/语言、关闭并发调度、错误重试、真实重复通知请求配置。
- 初轮各 8 项 UI：iPhone 7 项、iPad 6 项通过。提醒测试误点外层标签、iPad 日历底部按钮处于滚动区域之外；改为点击实际开关并检查值，日历操作固定到底部。之后 `iphone-polish.xcresult` 与 `ipad-polish.xcresult` 各 5 项全部通过，包括提醒开关/重新打开、日期重整、历史接续、首页分类和恢复进度。
- 最终底栏恢复后，`iphone-footer.xcresult` 和 `ipad-footer.xcresult` 各 2 项全部通过，检查今日完成后显示历史任务、无日期接续、全部完成状态、退出恢复和日历。只是样式恢复，没有改变已通过的任务与提醒模型。
- 筛选弹出菜单改为原生分区面板，内容类型有明确勾选，月份使用独立选择列表，重置和重新整理分开。其界面验证见后续记录。
- iOS 签名、模拟器与 Mac Catalyst 编译通过；最终筛选版日志为 `build-filter.log`、`build-device-filter.log`、`build-mac-filter.log`。初期失败及后续结果均保留在本机 `.ui-checks/inbox-reminder/`，不将初期失败计为全通过。
- 构建 10 已覆盖安装并启动于同一配对 iPhone 15；用户随后明确要求保留旧底栏及优化筛选，本轮最终使用构建 11。

提醒 UI 测试使用隔离的 Debug 通知服务，系统请求格式由单元测试核验；未把模拟测试等同于夜间真机通知投递。真实投递受通知权限、专注模式和系统设置影响。未执行真机照片删除；原有 iCloud 下载、权限切换与万张照片库性能验收边界保留。

筛选面板完成后，`iphone-filter.xcresult`、`ipad-filter.xcresult` 的类型/月份/重置/重整流程各 1 项通过。截图发现系统月份选择器使用了不一致的灰色背景，因此替换为同色原生列表；最终 `iphone-filter-colors.xcresult`、`ipad-filter-colors.xcresult` 各 1 项再次通过。最终三端编译成功，日志为 `build-filter-colors.log`、`build-device-filter-colors.log`、`build-mac-filter-colors.log`。此后未改变业务代码。

最终版本 1.1（11）已覆盖安装到同一配对 iPhone 15，回执 `device-install-latest.json`；通过 `--terminate-existing` 重启确保运行最新代码，启动回执为 `device-launch-latest.json`。未卸载 App 或清空个人数据。

按用户要求，每次版本更新后提交源码并同步至 https://github.com/luchuangao/DreamAlbum ，规则已写入 AGENTS.md。仓库保留初始提交历史，未包含构建缓存、签名材料、个人照片或原始本机测试产物。直接 Git HTTPS 连接超时后，通过已连接 GitHub 服务同步对象；文件内容使用 Git blob SHA 校验。
