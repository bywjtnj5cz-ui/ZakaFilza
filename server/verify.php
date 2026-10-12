<?php
/**
 * ZakaFilza 卡密 + 云控 后台 (单文件版)
 * 部署路径建议: /var/www/html/api/verify.php
 * 访问地址: http://your-server-ip/api/verify.php
 *
 * 数据库: SQLite (cards.db, 与本文件同目录自动生成)
 * 云控配置: settings.json (与本文件同目录自动生成)
 *
 * 路由:
 *   [App 公开]
 *   POST ?action=verify       App 卡密验证
 *   GET  ?action=config        App 拉取云端配置 JSON
 *
 *   [管理后台]
 *   GET  ?action=admin         HTML 管理后台首页
 *   POST ?action=gen           生成卡密
 *   GET  ?action=list          列出卡密
 *   POST ?action=unbind        解绑 UUID
 *   POST ?action=extend        续期
 *   POST ?action=delete        删除卡密
 *   GET  ?action=stats         统计
 *   GET  ?action=get_config    获取当前云控配置 (管理员)
 *   POST ?action=save_config   保存云控配置 (管理员)
 *   POST ?action=reset_config  重置云控配置为默认 (管理员)
 *
 * 管理认证: ?admin_token=xxx 或 X-Admin-Token 头
 */

// ==================== 配置 ====================
const ADMIN_TOKEN         = 'CHANGE_ME_TO_RANDOM_STRING';  // 必须修改!
const DB_FILE             = __DIR__ . '/cards.db';
const CONFIG_FILE         = __DIR__ . '/settings.json';
const DEFAULT_EXPIRE_DAYS = 30;
const CARD_PREFIX         = 'ZK';
const CARD_LENGTH         = 24;
const TIMEZONE            = 'Asia/Shanghai';

date_default_timezone_set(TIMEZONE);

// ==================== 数据库 ====================
function db() {
    static $pdo = null;
    if ($pdo === null) {
        $pdo = new PDO('sqlite:' . DB_FILE);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        $pdo->exec("CREATE TABLE IF NOT EXISTS cards (
            card_key      TEXT PRIMARY KEY,
            uuid          TEXT,
            model         TEXT,
            system_version TEXT,
            system_name   TEXT,
            member_level  INTEGER DEFAULT 1,
            expire_at     TEXT,
            activated_at  TEXT,
            created_at    TEXT,
            note          TEXT DEFAULT ''
        )");
        $pdo->exec("CREATE INDEX IF NOT EXISTS idx_uuid ON cards(uuid)");
    }
    return $pdo;
}

// ==================== 云控配置 ====================
function default_config() {
    return [
        'app_name'           => 'Zaka文件管理',
        'qq_group'           => '123456789',
        'wechat_official'    => 'ZakaOfficial',
        'version'            => '1.0.0',
        'announcement'       => "欢迎使用 Zaka 文件管理!\n\n首次使用请先选择与你系统版本匹配的漏洞利用方式, 获得文件系统访问权限后即可使用文件管理器.\n\n支持:\n• FilzaJailedDS (iOS 17-26)\n• FilzaSlop (iOS 18, 26, 27 beta)\n• Filza (越狱)",
        'config_url'         => '',  // 留空, 让 App 自行决定
        'verify_server_url'  => '',  // 留空, App 用内置默认地址
        'buttons' => [
            ['title' => '📁 文件管理', 'action' => 'open_file_manager', 'color' => '#FF6B9D'],
            ['title' => '⬇️ 下载中心', 'action' => 'open_file_manager', 'color' => '#6080FF'],
            ['title' => '🔄 更新地址', 'action' => 'update_url',         'color' => '#5CC873'],
            ['title' => '🔔 查看公告', 'action' => 'announcement',      'color' => '#FFA940'],
        ],
        'member_buttons' => [
            ['title' => '⚡ 一键美化', 'action' => 'download',     'color' => '#7C4DFF', 'download_url' => 'https://example.com/beautify_pack.zip', 'member_only' => true],
            ['title' => '💎 高级配置', 'action' => 'run_script',  'color' => '#00BCD4', 'script_path' => 'scripts/advanced.js', 'member_only' => true],
            ['title' => '🎮 游戏目录', 'action' => 'open_file_manager', 'color' => '#FF4081', 'member_only' => true],
            ['title' => '🗑️ 卸载美化', 'action' => 'uninstall',   'color' => '#F44336', 'member_only' => true],
        ],
        'download_shortcuts' => [
            ['name' => '美化包A', 'url' => 'https://example.com/pack_a.zip',     'target_dir' => '/var/mobile/Containers/Data/Application/Documents/Beautify', 'auto_import' => true],
            ['name' => '配置文件', 'url' => 'https://example.com/config.json',   'target_dir' => '/var/mobile/Containers/Data/Application/Documents/Config',   'auto_import' => true],
            ['name' => '资源包',  'url' => 'https://example.com/resources.zip',  'target_dir' => '/var/mobile/Containers/Data/Application/Documents/Resources', 'auto_import' => true],
        ],
    ];
}

function load_config() {
    if (!file_exists(CONFIG_FILE)) {
        $cfg = default_config();
        file_put_contents(CONFIG_FILE, json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
        return $cfg;
    }
    $data = json_decode(file_get_contents(CONFIG_FILE), true);
    if (!is_array($data)) {
        $cfg = default_config();
        file_put_contents(CONFIG_FILE, json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
        return $cfg;
    }
    // 合并默认值 (防止字段缺失)
    return array_merge(default_config(), $data);
}

function save_config_file($cfg) {
    // 只允许已知字段
    $allowed = ['app_name','qq_group','wechat_official','version','announcement',
                'config_url','verify_server_url','buttons','member_buttons','download_shortcuts'];
    $clean = [];
    foreach ($allowed as $k) {
        if (isset($cfg[$k])) $clean[$k] = $cfg[$k];
    }
    file_put_contents(CONFIG_FILE, json_encode($clean, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
    return $clean;
}

// ==================== 工具函数 ====================
function out($data, $code = 200) {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}

function gen_card_key() {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $len = strlen($chars);
    $rand = '';
    for ($i = 0; $i < CARD_LENGTH - strlen(CARD_PREFIX); $i++) {
        $rand .= $chars[random_int(0, $len - 1)];
    }
    return CARD_PREFIX . $rand;
}

function check_admin() {
    $token = $_GET['admin_token'] ?? $_SERVER['HTTP_X_ADMIN_TOKEN'] ?? '';
    if (!hash_equals(ADMIN_TOKEN, $token)) {
        out(['success' => false, 'message' => '管理员认证失败'], 403);
    }
}

function now_iso() { return date('c'); }
function add_days($days) { return date('c', time() + $days * 86400); }

// ==================== 路由 ====================
$action = $_GET['action'] ?? '';

switch ($action) {

// -------------------- App: 卡密验证 --------------------
case 'verify':
    $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
    $cardKey = trim($body['card_key'] ?? '');
    $uuid    = trim($body['uuid'] ?? '');
    $model   = trim($body['model'] ?? '');
    $sysVer  = trim($body['system_version'] ?? '');
    $sysName = trim($body['system_name'] ?? '');

    if ($cardKey === '' || $uuid === '') {
        out(['success' => false, 'message' => '卡密或设备 UUID 不能为空']);
    }

    $stmt = db()->prepare("SELECT * FROM cards WHERE card_key = ?");
    $stmt->execute([$cardKey]);
    $card = $stmt->fetch();

    if (!$card) {
        out(['success' => false, 'message' => '卡密不存在']);
    }

    if (empty($card['uuid'])) {
        $stmt = db()->prepare("UPDATE cards SET uuid=?, model=?, system_version=?, system_name=?, activated_at=? WHERE card_key=?");
        $stmt->execute([$uuid, $model, $sysVer, $sysName, now_iso(), $cardKey]);
        $card['uuid'] = $uuid;
        $card['model'] = $model;
        $card['system_version'] = $sysVer;
        $card['system_name'] = $sysName;
        $card['activated_at'] = now_iso();
    } elseif ($card['uuid'] !== $uuid) {
        out(['success' => false, 'message' => '该卡密已绑定其他设备, 请联系管理员解绑']);
    }

    $expireTs = strtotime($card['expire_at']);
    if ($expireTs === false || $expireTs < time()) {
        out(['success' => false, 'message' => '卡密已过期']);
    }

    $stmt = db()->prepare("UPDATE cards SET model=?, system_version=?, system_name=? WHERE card_key=?");
    $stmt->execute([$model, $sysVer, $sysName, $cardKey]);

    out([
        'success'      => true,
        'message'      => '验证成功',
        'expire_at'    => date('c', $expireTs),
        'member_level' => (int)$card['member_level'],
    ]);
    break;

// -------------------- App: 拉取云端配置 (公开) --------------------
case 'config':
    $cfg = load_config();
    // 如果服务器配置里没填 verify_server_url, 自动填上当前接口地址, 让 App 走这里验证
    if (empty($cfg['verify_server_url'])) {
        $protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
        $host = $_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? 'localhost';
        $script = $_SERVER['SCRIPT_NAME'] ?? '/api/verify.php';
        $cfg['verify_server_url'] = "$protocol://$host$script?action=verify";
    }
    // config_url 也自动指向自己 (App 通过这个地址再拉就是循环, 但不影响)
    if (empty($cfg['config_url'])) {
        $protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
        $host = $_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? 'localhost';
        $script = $_SERVER['SCRIPT_NAME'] ?? '/api/verify.php';
        $cfg['config_url'] = "$protocol://$host$script?action=config";
    }
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($cfg, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;

// -------------------- 管理: 生成卡密 --------------------
case 'gen':
    check_admin();
    $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
    $count       = max(1, min(100, (int)($body['count'] ?? 1)));
    $days        = (int)($body['days'] ?? DEFAULT_EXPIRE_DAYS);
    $memberLevel = (int)($body['member_level'] ?? 1);
    $note        = trim($body['note'] ?? '');
    $expireAt    = add_days($days);
    $now         = now_iso();

    $generated = [];
    $stmt = db()->prepare("INSERT OR IGNORE INTO cards (card_key, member_level, expire_at, created_at, note) VALUES (?, ?, ?, ?, ?)");
    for ($i = 0; $i < $count; $i++) {
        $retries = 0;
        do {
            $key = gen_card_key();
            $stmt->execute([$key, $memberLevel, $expireAt, $now, $note]);
            if ($stmt->rowCount() > 0) {
                $generated[] = $key;
                break;
            }
            $retries++;
        } while ($retries < 5);
    }
    out(['success' => true, 'count' => count($generated), 'cards' => $generated, 'expire_at' => $expireAt, 'days' => $days]);
    break;

// -------------------- 管理: 列出卡密 --------------------
case 'list':
    check_admin();
    $search = trim($_GET['q'] ?? '');
    $onlyActive = ($_GET['active'] ?? '0') === '1';
    $sql = "SELECT * FROM cards";
    $where = [];
    $params = [];
    if ($search !== '') {
        $where[] = "(card_key LIKE ? OR uuid LIKE ? OR note LIKE ?)";
        $kw = "%$search%";
        $params[] = $kw; $params[] = $kw; $params[] = $kw;
    }
    if ($onlyActive) {
        $where[] = "uuid IS NOT NULL AND uuid != ''";
    }
    if ($where) $sql .= " WHERE " . implode(' AND ', $where);
    $sql .= " ORDER BY created_at DESC";
    $stmt = db()->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();
    foreach ($rows as &$r) {
        $r['expired'] = strtotime($r['expire_at']) < time();
        $r['activated'] = !empty($r['uuid']);
    }
    out(['success' => true, 'count' => count($rows), 'cards' => $rows]);
    break;

// -------------------- 管理: 解绑 UUID --------------------
case 'unbind':
    check_admin();
    $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
    $cardKey = trim($body['card_key'] ?? '');
    if ($cardKey === '') out(['success' => false, 'message' => 'card_key 不能为空']);
    $stmt = db()->prepare("UPDATE cards SET uuid=NULL, model=NULL, system_version=NULL, system_name=NULL, activated_at=NULL WHERE card_key=?");
    $stmt->execute([$cardKey]);
    out(['success' => true, 'message' => '已解绑设备']);
    break;

// -------------------- 管理: 续期 --------------------
case 'extend':
    check_admin();
    $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
    $cardKey = trim($body['card_key'] ?? '');
    $days = (int)($body['days'] ?? 30);
    if ($cardKey === '') out(['success' => false, 'message' => 'card_key 不能为空']);
    $stmt = db()->prepare("SELECT expire_at FROM cards WHERE card_key=?");
    $stmt->execute([$cardKey]);
    $row = $stmt->fetch();
    if (!$row) out(['success' => false, 'message' => '卡密不存在']);
    $baseTs = strtotime($row['expire_at']);
    $baseTs = $baseTs > time() ? $baseTs : time();
    $newExpire = date('c', $baseTs + $days * 86400);
    $stmt = db()->prepare("UPDATE cards SET expire_at=? WHERE card_key=?");
    $stmt->execute([$newExpire, $cardKey]);
    out(['success' => true, 'message' => '续期成功', 'expire_at' => $newExpire]);
    break;

// -------------------- 管理: 删除卡密 --------------------
case 'delete':
    check_admin();
    $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
    $cardKey = trim($body['card_key'] ?? '');
    if ($cardKey === '') out(['success' => false, 'message' => 'card_key 不能为空']);
    $stmt = db()->prepare("DELETE FROM cards WHERE card_key=?");
    $stmt->execute([$cardKey]);
    out(['success' => true, 'message' => '已删除', 'affected' => $stmt->rowCount()]);
    break;

// -------------------- 管理: 统计 --------------------
case 'stats':
    check_admin();
    $total = (int)db()->query("SELECT COUNT(*) FROM cards")->fetchColumn();
    $active = (int)db()->query("SELECT COUNT(*) FROM cards WHERE uuid IS NOT NULL AND uuid != ''")->fetchColumn();
    $expired = (int)db()->query("SELECT COUNT(*) FROM cards WHERE expire_at < '" . date('c') . "'")->fetchColumn();
    $valid = $total - $expired;
    out([
        'success' => true,
        'stats' => [
            'total'      => $total,
            'activated'  => $active,
            'unused'     => $total - $active,
            'valid'      => $valid,
            'expired'    => $expired,
        ]
    ]);
    break;

// -------------------- 管理: 获取云控配置 --------------------
case 'get_config':
    check_admin();
    $cfg = load_config();
    // 不带自动填充的 config_url/verify_server_url, 返回原始保存值
    out(['success' => true, 'config' => $cfg]);
    break;

// -------------------- 管理: 保存云控配置 --------------------
case 'save_config':
    check_admin();
    $raw = file_get_contents('php://input');
    $cfg = json_decode($raw, true);
    if (!is_array($cfg)) {
        out(['success' => false, 'message' => '配置 JSON 无效: ' . json_last_error_msg()]);
    }
    $clean = save_config_file($cfg);
    out(['success' => true, 'message' => '云控配置已保存', 'config' => $clean]);
    break;

// -------------------- 管理: 重置云控配置 --------------------
case 'reset_config':
    check_admin();
    @unlink(CONFIG_FILE);
    $cfg = default_config();
    file_put_contents(CONFIG_FILE, json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
    out(['success' => true, 'message' => '云控配置已重置为默认', 'config' => $cfg]);
    break;

// -------------------- HTML 管理后台 --------------------
case 'admin':
case '':
    header('Content-Type: text/html; charset=utf-8');
    ?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Zaka 管理后台</title>
<style>
* { box-sizing: border-box; }
body { font-family: -apple-system, "PingFang SC", sans-serif; background: #f5f7fa; margin: 0; padding: 0; color: #333; }
.tabs { background: #fff; border-bottom: 1px solid #eee; padding: 0 20px; position: sticky; top: 0; z-index: 10; display: flex; gap: 4px; }
.tab { padding: 14px 20px; cursor: pointer; border-bottom: 3px solid transparent; font-weight: 500; color: #888; }
.tab.active { color: #FF6B9D; border-bottom-color: #FF6B9D; }
.container { max-width: 1100px; margin: 0 auto; padding: 20px; }
h1 { color: #FF6B9D; margin: 0 0 20px; }
.card { background: #fff; border-radius: 12px; padding: 20px; margin-bottom: 16px; box-shadow: 0 2px 8px rgba(0,0,0,.06); }
input, button, select, textarea { font-size: 14px; padding: 8px 12px; border-radius: 8px; border: 1px solid #ddd; outline: none; font-family: inherit; }
input:focus, textarea:focus, select:focus { border-color: #FF6B9D; }
button { background: #FF6B9D; color: white; border: none; cursor: pointer; margin: 4px 0; }
button:hover { background: #e85a86; }
button.gray { background: #888; }
button.gray:hover { background: #666; }
button.green { background: #5CC873; }
button.green:hover { background: #4ba862; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th, td { text-align: left; padding: 8px 6px; border-bottom: 1px solid #eee; }
th { background: #fafbfc; font-weight: 600; }
.tag { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 11px; }
.tag.green { background: #d4f4dd; color: #1b7a3d; }
.tag.red { background: #fcd6d6; color: #b00020; }
.tag.gray { background: #eee; color: #555; }
.tag.blue { background: #d6e4ff; color: #1c3eb8; }
.row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-bottom: 8px; }
.row input { flex: 1; min-width: 100px; }
.mono { font-family: SFMono-Regular, Menlo, monospace; }
.stats { display: flex; gap: 12px; flex-wrap: wrap; }
.stat-box { flex: 1; min-width: 100px; padding: 12px; background: linear-gradient(135deg, #fff, #f9f9f9); border-radius: 10px; text-align: center; }
.stat-box .num { font-size: 24px; font-weight: bold; color: #FF6B9D; }
.stat-box .label { font-size: 12px; color: #888; margin-top: 4px; }
.notice { padding: 10px 14px; background: #fff8e1; border-left: 4px solid #FFA940; border-radius: 6px; margin-bottom: 12px; font-size: 13px; }
.config-section { display: none; }
.config-section.active { display: block; }
textarea { width: 100%; min-height: 320px; font-family: SFMono-Regular, Menlo, monospace; font-size: 12px; }
.btn-array-item { background: #f9f9f9; border: 1px solid #e0e0e0; border-radius: 8px; padding: 10px; margin-bottom: 8px; }
.btn-array-item .row input { font-size: 13px; }
</style>
</head>
<body>
<div class="tabs">
  <div class="tab active" onclick="switchTab('cards')">🔑 卡密管理</div>
  <div class="tab" onclick="switchTab('config')">☁️ 云控配置</div>
</div>
<div class="container">
<h1>Zaka 管理后台</h1>
<div class="notice">
  App 验证地址: <span class="mono" id="verify-url"></span><br>
  App 配置地址: <span class="mono" id="config-url"></span><br>
  首次使用请修改 <code>verify.php</code> 里的 <code>ADMIN_TOKEN</code> 常量。
</div>
<div class="row">
  <input id="token" placeholder="管理员 Token (ADMIN_TOKEN)" type="password" style="min-width:240px">
  <button onclick="loadAll()">登录</button>
</div>

<!-- ============== Tab: 卡密管理 ============== -->
<div id="tab-cards" class="config-section active">
  <div class="card">
    <h3>📊 统计</h3>
    <div class="stats">
      <div class="stat-box"><div class="num" id="s-total">-</div><div class="label">总卡密</div></div>
      <div class="stat-box"><div class="num" id="s-active">-</div><div class="label">已激活</div></div>
      <div class="stat-box"><div class="num" id="s-valid">-</div><div class="label">有效</div></div>
      <div class="stat-box"><div class="num" id="s-expired">-</div><div class="label">已过期</div></div>
    </div>
  </div>
  <div class="card">
    <h3>➕ 生成卡密</h3>
    <div class="row">
      数量 <input id="gen-count" type="number" value="1" min="1" max="100" style="max-width:80px">
      有效天数 <input id="gen-days" type="number" value="30" style="max-width:80px">
      会员等级 <select id="gen-level"><option value="1">普通</option><option value="2">高级</option><option value="3">VIP</option></select>
      备注 <input id="gen-note" placeholder="备注(可选)">
      <button onclick="genCard()">生成</button>
    </div>
    <div id="gen-result" class="mono" style="white-space:pre-wrap;background:#f9f9f9;padding:10px;border-radius:6px;margin-top:8px;display:none"></div>
  </div>
  <div class="card">
    <h3>📋 卡密列表</h3>
    <div class="row">
      <input id="search" placeholder="搜索卡密/UUID/备注" onkeydown="if(event.key==='Enter')loadList()">
      <button onclick="loadList()">搜索</button>
      <label style="font-size:13px"><input type="checkbox" id="onlyActive"> 仅已激活</label>
      <button class="gray" onclick="loadList()">刷新</button>
    </div>
    <div style="overflow-x:auto">
      <table>
        <thead><tr>
          <th>卡密</th><th>UUID</th><th>设备</th><th>系统</th><th>等级</th><th>到期时间</th><th>状态</th><th>操作</th>
        </tr></thead>
        <tbody id="card-list"></tbody>
      </table>
    </div>
  </div>
</div>

<!-- ============== Tab: 云控配置 ============== -->
<div id="tab-config" class="config-section">
  <div class="card">
    <h3>📝 基础信息</h3>
    <div class="row"><label style="min-width:110px">应用名</label><input id="c-app_name"></div>
    <div class="row"><label style="min-width:110px">版本号</label><input id="c-version"></div>
    <div class="row"><label style="min-width:110px">QQ 群</label><input id="c-qq_group"></div>
    <div class="row"><label style="min-width:110px">微信公众号</label><input id="c-wechat_official"></div>
    <div class="row"><label style="min-width:110px">验证服务器</label><input id="c-verify_server_url" placeholder="留空则自动用本接口"></div>
    <div class="row"><label style="min-width:110px">配置地址</label><input id="c-config_url" placeholder="留空则自动用本接口"></div>
    <div class="row" style="align-items:flex-start"><label style="min-width:110px">公告</label><textarea id="c-announcement" style="min-height:100px"></textarea></div>
  </div>

  <div class="card">
    <h3>🔘 普通按钮 <button class="gray" onclick="addButton('buttons')" style="float:right">+ 添加按钮</button></h3>
    <div id="c-buttons"></div>
  </div>

  <div class="card">
    <h3>💎 会员按钮 <button class="gray" onclick="addButton('member_buttons')" style="float:right">+ 添加按钮</button></h3>
    <div id="c-member_buttons"></div>
  </div>

  <div class="card">
    <h3>⬇️ 一键下载直链 <button class="gray" onclick="addShortcut()" style="float:right">+ 添加</button></h3>
    <div id="c-download_shortcuts"></div>
  </div>

  <div class="card">
    <div class="row">
      <button class="green" onclick="saveConfig()">💾 保存配置</button>
      <button class="gray" onclick="loadConfig()">↻ 重新加载</button>
      <button class="gray" onclick="resetConfig()" style="background:#F44336">🗑️ 重置为默认</button>
    </div>
    <div style="margin-top:12px">
      <h4>原始 JSON (高级用户可直接编辑)</h4>
      <textarea id="c-raw-json"></textarea>
      <div class="row" style="margin-top:6px"><button onclick="applyRawJson()">应用原始 JSON</button></div>
    </div>
  </div>
</div>

</div>

<script>
const TOKEN_INPUT = document.getElementById('token');
const API_BASE = location.href.split('?')[0];
let CURRENT_CONFIG = null;

function tok() { return '?admin_token=' + encodeURIComponent(TOKEN_INPUT.value); }
function esc(s) { return String(s ?? '').replace(/[<>&]/g, c => ({'<':'&lt;','>':'&gt;','&':'&amp;'}[c])); }
function fmtDate(s) { if (!s) return '-'; const d = new Date(s); return isNaN(d) ? s : d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'); }

function switchTab(name) {
  document.querySelectorAll('.tab').forEach((t, i) => {
    const target = i === 0 ? 'cards' : 'config';
    t.classList.toggle('active', target === name);
  });
  document.getElementById('tab-cards').classList.toggle('active', name === 'cards');
  document.getElementById('tab-config').classList.toggle('active', name === 'config');
  if (name === 'config' && CURRENT_CONFIG === null) loadConfig();
}

async function api(action, method='GET', body=null) {
  const url = API_BASE + '?action=' + action + '&' + tok().slice(1);
  const opt = { method, headers: {} };
  if (body) { opt.headers['Content-Type'] = 'application/json'; opt.body = JSON.stringify(body); }
  const r = await fetch(url, opt);
  return await r.json();
}

function loadAll() {
  if (!TOKEN_INPUT.value) { alert('请输入管理员 Token'); return; }
  const u = API_BASE;
  document.getElementById('verify-url').textContent = u + '?action=verify';
  document.getElementById('config-url').textContent = u + '?action=config';
  loadStats(); loadList(); loadConfig();
}

async function loadStats() {
  const r = await api('stats');
  if (!r.success) { alert(r.message); return; }
  document.getElementById('s-total').textContent = r.stats.total;
  document.getElementById('s-active').textContent = r.stats.activated;
  document.getElementById('s-valid').textContent = r.stats.valid;
  document.getElementById('s-expired').textContent = r.stats.expired;
}

async function genCard() {
  const body = {
    count: parseInt(document.getElementById('gen-count').value),
    days: parseInt(document.getElementById('gen-days').value),
    member_level: parseInt(document.getElementById('gen-level').value),
    note: document.getElementById('gen-note').value
  };
  const r = await api('gen', 'POST', body);
  const div = document.getElementById('gen-result');
  if (!r.success) { div.textContent = '错误: ' + r.message; div.style.color = 'red'; div.style.display = 'block'; return; }
  div.style.color = '';
  div.textContent = '生成 ' + r.count + ' 个, 到期: ' + fmtDate(r.expire_at) + '\n\n' + r.cards.join('\n');
  div.style.display = 'block';
  loadStats(); loadList();
}

async function loadList() {
  const q = document.getElementById('search').value;
  const onlyActive = document.getElementById('onlyActive').checked ? '1' : '0';
  const url = API_BASE + '?action=list&q=' + encodeURIComponent(q) + '&active=' + onlyActive + '&' + tok().slice(1);
  const r = await (await fetch(url)).json();
  if (!r.success) { alert(r.message); return; }
  const tbody = document.getElementById('card-list');
  tbody.innerHTML = '';
  if (r.cards.length === 0) {
    tbody.innerHTML = '<tr><td colspan="8" style="text-align:center;color:#999;padding:20px">无数据</td></tr>';
    return;
  }
  for (const c of r.cards) {
    const tr = document.createElement('tr');
    const statusTag = c.activated
      ? (c.expired ? '<span class="tag red">已过期</span>' : '<span class="tag green">已激活</span>')
      : (c.expired ? '<span class="tag red">已过期</span>' : '<span class="tag blue">未激活</span>');
    const actions = [];
    if (c.activated) actions.push(`<button class="gray" onclick="unbind('${c.card_key}')">解绑</button>`);
    actions.push(`<button class="gray" onclick="extendCard('${c.card_key}')">续期</button>`);
    actions.push(`<button class="gray" onclick="deleteCard('${c.card_key}')">删除</button>`);
    tr.innerHTML = `
      <td class="mono">${esc(c.card_key)}</td>
      <td class="mono" style="max-width:180px;overflow:hidden;text-overflow:ellipsis">${esc(c.uuid) || '-'}</td>
      <td>${esc(c.model) || '-'}</td>
      <td>${esc(c.system_name) || ''} ${esc(c.system_version) || ''}</td>
      <td>L${c.member_level}</td>
      <td>${fmtDate(c.expire_at)}</td>
      <td>${statusTag}</td>
      <td>${actions.join('')}</td>`;
    tbody.appendChild(tr);
  }
}

async function unbind(key) {
  if (!confirm('确定解绑 ' + key + ' 的设备?')) return;
  const r = await api('unbind', 'POST', { card_key: key });
  alert(r.message); loadList();
}

async function extendCard(key) {
  const days = prompt('续期天数 (默认 30)', '30');
  if (!days) return;
  const r = await api('extend', 'POST', { card_key: key, days: parseInt(days) });
  alert(r.message + (r.expire_at ? ' 新到期: ' + fmtDate(r.expire_at) : ''));
  loadList();
}

async function deleteCard(key) {
  if (!confirm('确定删除卡密 ' + key + '? 此操作不可恢复')) return;
  const r = await api('delete', 'POST', { card_key: key });
  alert(r.message); loadStats(); loadList();
}

// ==================== 云控配置 ====================
async function loadConfig() {
  const r = await api('get_config');
  if (!r.success) { alert(r.message); return; }
  CURRENT_CONFIG = r.config;
  renderConfigForm(r.config);
  document.getElementById('c-raw-json').value = JSON.stringify(r.config, null, 2);
}

function renderConfigForm(cfg) {
  document.getElementById('c-app_name').value = cfg.app_name ?? '';
  document.getElementById('c-version').value = cfg.version ?? '';
  document.getElementById('c-qq_group').value = cfg.qq_group ?? '';
  document.getElementById('c-wechat_official').value = cfg.wechat_official ?? '';
  document.getElementById('c-verify_server_url').value = cfg.verify_server_url ?? '';
  document.getElementById('c-config_url').value = cfg.config_url ?? '';
  document.getElementById('c-announcement').value = cfg.announcement ?? '';
  renderButtons('buttons', cfg.buttons ?? []);
  renderButtons('member_buttons', cfg.member_buttons ?? []);
  renderShortcuts(cfg.download_shortcuts ?? []);
}

function collectConfig() {
  const cfg = {
    app_name: document.getElementById('c-app_name').value,
    version: document.getElementById('c-version').value,
    qq_group: document.getElementById('c-qq_group').value,
    wechat_official: document.getElementById('c-wechat_official').value,
    verify_server_url: document.getElementById('c-verify_server_url').value,
    config_url: document.getElementById('c-config_url').value,
    announcement: document.getElementById('c-announcement').value,
    buttons: collectButtons('buttons'),
    member_buttons: collectButtons('member_buttons'),
    download_shortcuts: collectShortcuts(),
  };
  return cfg;
}

const ACTIONS = ['open_file_manager','download','run_script','open_url','update_url','announcement','uninstall','custom'];

function renderButtons(fieldId, arr) {
  const container = document.getElementById('c-' + fieldId);
  container.innerHTML = '';
  arr.forEach((b, idx) => {
    const div = document.createElement('div');
    div.className = 'btn-array-item';
    div.innerHTML = `
      <div class="row">
        <input placeholder="按钮标题" value="${esc(b.title)}" data-f="title" style="flex:2">
        <select data-f="action" style="max-width:180px">
          ${ACTIONS.map(a => `<option value="${a}" ${a === b.action ? 'selected' : ''}>${a}</option>`).join('')}
        </select>
        <input placeholder="颜色 #FF6B9D" value="${esc(b.color ?? '')}" data-f="color" style="max-width:120px">
        <button class="gray" onclick="removeItem(this, '${fieldId}')">✕</button>
      </div>
      <div class="row">
        <input placeholder="download_url (action=download 时)" value="${esc(b.download_url ?? '')}" data-f="download_url">
      </div>
      <div class="row">
        <input placeholder="script_path (action=run_script 时)" value="${esc(b.script_path ?? '')}" data-f="script_path">
      </div>
      <div class="row">
        <input placeholder="open_url (action=open_url 时)" value="${esc(b.open_url ?? '')}" data-f="open_url">
        <label style="font-size:12px"><input type="checkbox" data-f="member_only" ${b.member_only ? 'checked' : ''}> 会员专属</label>
      </div>
    `;
    container.appendChild(div);
  });
}

function collectButtons(fieldId) {
  const container = document.getElementById('c-' + fieldId);
  const items = container.querySelectorAll('.btn-array-item');
  const out = [];
  items.forEach(item => {
    const b = {};
    b.title = item.querySelector('[data-f="title"]').value;
    b.action = item.querySelector('[data-f="action"]').value;
    b.color = item.querySelector('[data-f="color"]').value || null;
    const du = item.querySelector('[data-f="download_url"]').value; if (du) b.download_url = du;
    const sp = item.querySelector('[data-f="script_path"]').value; if (sp) b.script_path = sp;
    const ou = item.querySelector('[data-f="open_url"]').value; if (ou) b.open_url = ou;
    b.member_only = item.querySelector('[data-f="member_only"]').checked;
    out.push(b);
  });
  return out;
}

function addButton(fieldId) {
  const cfg = CURRENT_CONFIG || {};
  cfg[fieldId] = cfg[fieldId] || [];
  cfg[fieldId].push({ title: '新按钮', action: 'open_file_manager', color: '#FF6B9D', member_only: fieldId === 'member_buttons' });
  renderButtons(fieldId, cfg[fieldId]);
}

function removeItem(btn, fieldId) {
  if (!confirm('确定删除此按钮?')) return;
  const item = btn.closest('.btn-array-item');
  const container = document.getElementById('c-' + fieldId);
  const idx = Array.from(container.children).indexOf(item);
  CURRENT_CONFIG[fieldId].splice(idx, 1);
  renderButtons(fieldId, CURRENT_CONFIG[fieldId]);
}

function renderShortcuts(arr) {
  const container = document.getElementById('c-download_shortcuts');
  container.innerHTML = '';
  arr.forEach((s, idx) => {
    const div = document.createElement('div');
    div.className = 'btn-array-item';
    div.innerHTML = `
      <div class="row">
        <input placeholder="名称" value="${esc(s.name)}" data-f="name" style="flex:1">
        <button class="gray" onclick="removeShortcut(this)">✕</button>
      </div>
      <div class="row"><input placeholder="直链 URL" value="${esc(s.url)}" data-f="url"></div>
      <div class="row"><input placeholder="目标目录 (绝对路径)" value="${esc(s.target_dir)}" data-f="target_dir"></div>
      <div class="row"><label style="font-size:12px"><input type="checkbox" data-f="auto_import" ${s.auto_import ? 'checked' : ''}> 下载后自动导入</label></div>
    `;
    container.appendChild(div);
  });
}

function collectShortcuts() {
  const container = document.getElementById('c-download_shortcuts');
  const items = container.querySelectorAll('.btn-array-item');
  const out = [];
  items.forEach(item => {
    out.push({
      name: item.querySelector('[data-f="name"]').value,
      url: item.querySelector('[data-f="url"]').value,
      target_dir: item.querySelector('[data-f="target_dir"]').value,
      auto_import: item.querySelector('[data-f="auto_import"]').checked
    });
  });
  return out;
}

function addShortcut() {
  CURRENT_CONFIG = CURRENT_CONFIG || {};
  CURRENT_CONFIG.download_shortcuts = CURRENT_CONFIG.download_shortcuts || [];
  CURRENT_CONFIG.download_shortcuts.push({ name: '新下载', url: '', target_dir: '', auto_import: true });
  renderShortcuts(CURRENT_CONFIG.download_shortcuts);
}

function removeShortcut(btn) {
  if (!confirm('确定删除此下载项?')) return;
  const item = btn.closest('.btn-array-item');
  const container = document.getElementById('c-download_shortcuts');
  const idx = Array.from(container.children).indexOf(item);
  CURRENT_CONFIG.download_shortcuts.splice(idx, 1);
  renderShortcuts(CURRENT_CONFIG.download_shortcuts);
}

async function saveConfig() {
  let cfg;
  try { cfg = collectConfig(); } catch(e) { alert('收集配置出错: ' + e.message); return; }
  const r = await api('save_config', 'POST', cfg);
  if (!r.success) { alert('保存失败: ' + r.message); return; }
  alert('✅ 云控配置已保存\nApp 下次启动会自动拉取最新配置');
  document.getElementById('c-raw-json').value = JSON.stringify(r.config, null, 2);
}

async function resetConfig() {
  if (!confirm('确定重置云控配置为默认? 所有自定义按钮和下载项将丢失')) return;
  const r = await api('reset_config', 'POST');
  if (!r.success) { alert(r.message); return; }
  alert('已重置为默认');
  CURRENT_CONFIG = r.config;
  renderConfigForm(r.config);
  document.getElementById('c-raw-json').value = JSON.stringify(r.config, null, 2);
}

function applyRawJson() {
  try {
    const cfg = JSON.parse(document.getElementById('c-raw-json').value);
    CURRENT_CONFIG = cfg;
    renderConfigForm(cfg);
    alert('已加载, 记得点保存按钮持久化');
  } catch(e) {
    alert('JSON 解析失败: ' + e.message);
  }
}
</script>
</body>
</html>
    <?php
    break;

default:
    out(['success' => false, 'message' => '未知 action: ' . htmlspecialchars($action)]);
}
