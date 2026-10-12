<?php
/**
 * ZakaFilza 卡密验证服务器 (单文件版)
 * 部署路径建议: /var/www/html/api/verify.php
 * 访问地址: http://your-server-ip/api/verify.php
 *
 * 数据库: SQLite (自动建库, 文件 cards.db 与本文件同目录)
 *
 * 路由:
 *   POST ?action=verify        App 卡密验证 (公开)
 *   GET  ?action=list          管理后台: 列出所有卡密
 *   POST ?action=gen           管理后台: 生成卡密
 *   POST ?action=unbind        管理后台: 解绑 UUID
 *   POST ?action=delete        管理后台: 删除卡密
 *   POST ?action=extend        管理后台: 续期
 *   GET  ?action=stats         管理后台: 统计信息
 *
 * 管理 token 通过 ?admin_token=xxx 或 X-Admin-Token 头传入
 * 首次运行后请修改下面的 ADMIN_TOKEN
 */

// ==================== 配置 ====================
const ADMIN_TOKEN   = 'CHANGE_ME_TO_RANDOM_STRING';  // 必须修改! 建议改成32位随机字符串
const DB_FILE        = __DIR__ . '/cards.db';
const DEFAULT_EXPIRE_DAYS = 30;       // 默认有效期 30 天
const CARD_PREFIX    = 'ZK';          // 卡密前缀
const CARD_LENGTH    = 24;            // 卡密总长度 (含前缀)
const TIMEZONE        = 'Asia/Shanghai';

date_default_timezone_set(TIMEZONE);

// ==================== 数据库 ====================
function db() {
    static $pdo = null;
    if ($pdo === null) {
        $pdo = new PDO('sqlite:' . DB_FILE);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        // 自动建表
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

// ==================== 工具函数 ====================
function out($data, $code = 200) {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}

function gen_card_key() {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 去除易混淆字符
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

function now_iso() {
    return date('c');
}

function add_days($days) {
    return date('c', time() + $days * 86400);
}

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

    // 1. UUID 绑定检查
    if (empty($card['uuid'])) {
        // 首次激活, 绑定 UUID
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

    // 2. 过期检查
    $expireTs = strtotime($card['expire_at']);
    if ($expireTs === false || $expireTs < time()) {
        out(['success' => false, 'message' => '卡密已过期']);
    }

    // 3. 同步设备信息
    $stmt = db()->prepare("UPDATE cards SET model=?, system_version=?, system_name=? WHERE card_key=?");
    $stmt->execute([$model, $sysVer, $sysName, $cardKey]);

    out([
        'success'      => true,
        'message'      => '验证成功',
        'expire_at'    => date('c', $expireTs),
        'member_level' => (int)$card['member_level'],
    ]);
    break;

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
    // 标记过期状态
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
    // 如果未过期, 在原 expire_at 上加; 如果已过期, 从现在加
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
            'unused'      => $total - $active,
            'valid'      => $valid,
            'expired'    => $expired,
        ]
    ]);
    break;

// -------------------- 简易 HTML 管理后台 --------------------
case 'admin':
case '':
    // 仅返回一个简单的 HTML 管理界面, 必须输入 token
    header('Content-Type: text/html; charset=utf-8');
    ?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Zaka 卡密管理后台</title>
<style>
* { box-sizing: border-box; }
body { font-family: -apple-system, "PingFang SC", sans-serif; background: #f5f7fa; margin: 0; padding: 20px; color: #333; }
.container { max-width: 1100px; margin: 0 auto; }
h1 { color: #FF6B9D; margin-top: 0; }
.card { background: #fff; border-radius: 12px; padding: 20px; margin-bottom: 16px; box-shadow: 0 2px 8px rgba(0,0,0,.06); }
input, button, select { font-size: 14px; padding: 8px 12px; border-radius: 8px; border: 1px solid #ddd; outline: none; }
button { background: #FF6B9D; color: white; border: none; cursor: pointer; margin: 4px 0; }
button:hover { background: #e85a86; }
button.gray { background: #888; }
button.gray:hover { background: #666; }
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
</style>
</head>
<body>
<div class="container">
<h1>🔑 Zaka 卡密管理后台</h1>
<div class="notice">
  验证地址 (App 端使用): <span class="mono" id="verify-url"></span><br>
  首次使用请修改 <code>verify.php</code> 里的 <code>ADMIN_TOKEN</code> 常量。
</div>

<div class="row">
  <input id="token" placeholder="管理员 Token (ADMIN_TOKEN)" type="password" style="min-width:240px">
  <button onclick="loadAll()">登录</button>
</div>

<div class="card">
  <h3>📊 统计</h3>
  <div class="stats" id="stats">
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

<script>
const TOKEN_INPUT = document.getElementById('token');
const API_BASE = location.href.split('?')[0];

function tok() { return '?admin_token=' + encodeURIComponent(TOKEN_INPUT.value); }

function esc(s) { return String(s ?? '').replace(/[<>&]/g, c => ({'<':'&lt;','>':'&gt;','&':'&amp;'}[c])); }

function fmtDate(s) {
  if (!s) return '-';
  const d = new Date(s);
  return isNaN(d) ? s : d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}

async function api(action, method='GET', body=null) {
  const url = API_BASE + '?action=' + action + (action !== 'list' && action !== 'stats' ? '' : '') + '&' + tok().slice(1);
  const opt = { method, headers: {} };
  if (body) { opt.headers['Content-Type'] = 'application/json'; opt.body = JSON.stringify(body); }
  const r = await fetch(url, opt);
  return await r.json();
}

async function loadAll() {
  if (!TOKEN_INPUT.value) { alert('请输入管理员 Token'); return; }
  document.getElementById('verify-url').textContent = API_BASE + '?action=verify';
  loadStats();
  loadList();
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
</script>
</body>
</html>
    <?php
    break;

default:
    out(['success' => false, 'message' => '未知 action: ' . htmlspecialchars($action)]);
}
