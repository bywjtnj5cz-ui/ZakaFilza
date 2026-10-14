<?php
/**
 * MoyuTool 卡密 + 云控 后台 (单文件版)
 * 部署路径建议: /var/www/html/api/verify.php
 * 访问地址: http://your-server-ip/api/verify.php
 *
 * 存储: 纯 JSON 文件 (cards.json / settings.json, 与本文件同目录自动生成)
 *       不需要任何数据库扩展, PHP 原生即可运行
 *       若目录不可写, 自动降级到系统临时目录
 *
 * 管理员 Token 优先级:
 *   1. 同目录 admin_token.txt 文件内容 (推荐, 重新上传 verify.php 不会丢失)
 *   2. 下方 ADMIN_TOKEN 常量
 *
 * 路由:
 *   [App 公开]
 *   POST ?action=verify       App 卡密验证
 *   GET  ?action=config        App 拉取云端配置 JSON
 *   GET  ?action=health        部署诊断
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
 *   POST ?action=upload           上传文件 (管理员, multipart 字段名 file)
 *   GET  ?action=uploads          列出已上传文件 (管理员)
 *   GET  ?action=download_upload  下载已上传文件 (管理员)
 *   POST ?action=delete_upload    删除已上传文件 (管理员)
 *
 * 管理认证: ?admin_token=xxx 或 X-Admin-Token 头
 */

// ==================== 配置 ====================
const ADMIN_TOKEN         = 'CHANGE_ME_TO_RANDOM_STRING';  // 必须修改 (或用 admin_token.txt)
const DEFAULT_EXPIRE_DAYS = 30;
const CARD_PREFIX         = 'ZK';
const CARD_LENGTH         = 24;
const TIMEZONE            = 'Asia/Shanghai';

date_default_timezone_set(TIMEZONE);

// ==================== 存储层 (纯 JSON 文件, 无数据库依赖) ====================
function data_dir() {
    static $dir = null;
    if ($dir !== null) return $dir;
    // 优先脚本同目录的 data/ 子目录 (跨请求/跨进程稳定一致, 防止配置"保存后丢失")
    // 其次脚本同目录, 最后才降级系统临时目录
    foreach ([__DIR__ . '/data', __DIR__, sys_get_temp_dir()] as $d) {
        if (!is_dir($d)) @mkdir($d, 0777, true);
        if (is_dir($d) && is_writable($d)) { $dir = $d; return $dir; }
    }
    $dir = sys_get_temp_dir();
    return $dir;
}

function data_file($name) { return data_dir() . '/' . $name; }

function admin_token() {
    // 同目录 admin_token.txt 优先 (更新 verify.php 不丢 token)
    $f = __DIR__ . '/admin_token.txt';
    if (is_readable($f)) {
        $t = trim(file_get_contents($f));
        if ($t !== '') return $t;
    }
    return ADMIN_TOKEN;
}

function load_cards() {
    $f = data_file('cards.json');
    if (!file_exists($f)) return [];
    $data = json_decode(file_get_contents($f), true);
    return is_array($data) ? $data : [];
}

function save_cards($cards) {
    return file_put_contents(
        data_file('cards.json'),
        json_encode(array_values($cards), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE),
        LOCK_EX
    );
}

// ==================== 云控配置 ====================
function default_config() {
    return [
        'app_name'           => '墨鱼Tool',
        'qq_group'           => '',
        'wechat_official'    => '',
        'version'            => '1.0.0',
        'announcement'       => "欢迎使用 墨鱼Tool!\n\n首次使用请先选择与你系统版本匹配的漏洞利用方式, 获得文件系统访问权限后即可使用文件管理器.\n\n支持:\n• FilzaJailedDS (iOS 17-26)\n• FilzaSlop (iOS 18, 26, 27 beta)\n• Filza (巨魔)",
        'config_url'         => '',  // 留空, 让 App 自行决定
        'verify_server_url'  => '',  // 留空, App 用内置默认地址
        'min_version'        => '1.0.0',  // 最低可用版本, 低于此版本 App 启动即锁定 (版本封杀开关)
        'theme' => [
            'primary'       => '#0A84FF',
            'accent'        => '#3E434C',
            'background'    => 'dark',     // dark | light | aurora(兼容旧值, 效果=dark)
            'corner_radius' => 18,
            'button_height' => 52,
            'font_scale'    => 1.0,
            'card_opacity'  => 0.82,
        ],
        'kill_switch'        => false,       // 急停: true = 全体停用
        'kill_message'       => '服务已暂停，请联系管理员',
        'sources'            => [],          // 备用配置线路 (主线路挂了自动切换)
        'buttons' => [
            ['title' => '📁 文件管理', 'action' => 'open_file_manager', 'color' => '#0A84FF', 'shortcut' => 'cmd+1'],
            ['title' => '⬇️ 下载中心', 'action' => 'open_file_manager', 'color' => '#3E434C', 'shortcut' => 'cmd+2'],
            ['title' => '🔄 更新地址', 'action' => 'update_url',         'color' => '#5CC873'],
            ['title' => '🔔 查看公告', 'action' => 'announcement',      'color' => '#FFA940'],
            ['title' => '🔍 目录检测', 'action' => 'game_diagnostic', 'color' => '#FF6B9D'],
        ],
        'member_buttons' => [
            ['title' => '⚡ 一键美化', 'action' => 'download',     'color' => '#0A84FF', 'download_url' => '', 'member_only' => true, 'confirm_text' => '确定要下载并导入美化包吗？', 'unzip' => true, 'params' => ['target_dir' => '@game:paks']],
            ['title' => '💎 高级配置', 'action' => 'run_script',  'color' => '#00BCD4', 'member_only' => true, 'script' => "// 云端 JS 脚本示例\nconsole.log('高级配置脚本已执行'); log('这是原生控制台输出');"],
            ['title' => '🎮 游戏目录', 'action' => 'open_file_manager', 'color' => '#FF4081', 'member_only' => true, 'path' => '@game:paks'],
            ['title' => '🗑️ 卸载美化', 'action' => 'uninstall',   'color' => '#F44336', 'member_only' => true, 'confirm_text' => '确定要卸载美化吗？将删除已配置的美化文件。', 'paths' => ['/var/mobile/Containers/Data/Application/Documents/Beautify']],
        ],
        'earphone_buttons' => [
            // 耳机档位专属按钮 (member_level = 2 可见), 默认空
        ],
        'download_shortcuts' => [],
        'game_dirs' => [
            'bundle_id' => 'com.tencent.tmgp.pubgmhd',
            'saved_rel' => 'Documents/ShadowTrackerExtra/Saved',
            'targets' => [
                ['key' => 'paks',       'label' => 'Paks',       'rel' => 'Paks'],
                ['key' => 'avatarpaks', 'label' => 'AvatarPaks', 'rel' => 'Paks/avatarpaks'],
                ['key' => 'saveGames',   'label' => 'SaveGames',  'rel' => 'SaveGames'],
            ],
        ],
        // 首页轮播图 (image_url 图片直链, link_url 点击跳转, 可留空)
        'banners' => [],
        // 启动自动美化: 已获得文件权限后自动下载并导入对应配置包
        'auto_beautify' => [
            'enabled'     => false,
            'category_id' => '',   // 为空则匹配目标配置包所在分类
            'file_id'     => '',   // 配置包 id (对应 categories[].files[].id)
        ],
        // 配置分类树 (美化 / 画质 / 功能), App 按分类渲染卡片并下载安装
        'categories' => [
            [
                'id' => 'beautify', 'title' => '⚡ 美化', 'type' => 'beautify',
                'icon' => 'sparkles', 'member_only' => true, 'files' => [],
            ],
            [
                'id' => 'quality', 'title' => '🎨 画质', 'type' => 'quality',
                'icon' => 'paintpalette', 'member_only' => true, 'files' => [],
            ],
            [
                'id' => 'function', 'title' => '⚙️ 功能', 'type' => 'function',
                'icon' => 'gearshape', 'member_only' => false, 'files' => [],
            ],
        ],
    ];
}

function load_config() {
    $f = data_file('settings.json');
    if (!file_exists($f)) {
        $cfg = default_config();
        @file_put_contents($f, json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
        return $cfg;
    }
    $data = json_decode(file_get_contents($f), true);
    if (!is_array($data)) {
        $cfg = default_config();
        @file_put_contents($f, json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
        return $cfg;
    }
    // 合并默认值 (防止字段缺失)
    return array_merge(default_config(), $data);
}

function save_config_file($cfg) {
    // 只允许已知字段
    $allowed = ['app_name','qq_group','wechat_official','version','announcement',
                'config_url','verify_server_url','min_version','buttons','member_buttons','earphone_buttons','download_shortcuts','game_dirs',
                'theme','kill_switch','kill_message','sources','banners','auto_beautify','categories'];
    $clean = [];
    foreach ($allowed as $k) {
        if (isset($cfg[$k])) $clean[$k] = $cfg[$k];
    }
    file_put_contents(
        data_file('settings.json'),
        json_encode($clean, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE),
        LOCK_EX
    );
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
    if ($token === '' || !hash_equals(admin_token(), $token)) {
        out(['success' => false, 'message' => '管理员认证失败'], 403);
    }
}

function now_iso() { return date('c'); }
function add_days($days) { return date('c', time() + $days * 86400); }

function find_card_index($cards, $cardKey) {
    foreach ($cards as $i => $c) {
        if (($c['card_key'] ?? '') === $cardKey) return $i;
    }
    return -1;
}

// ==================== 文件上传 (管理员专属) ====================
function uploads_dir() {
    $dir = data_dir() . '/uploads';
    if (!is_dir($dir)) @mkdir($dir, 0777, true);
    return $dir;
}

function sanitize_filename($name) {
    $name = basename(str_replace('\\', '/', (string)$name));
    $clean = preg_replace('/[^\x{4e00}-\x{9fa5}A-Za-z0-9._()\- ]/u', '', $name);
    if ($clean === null || $clean === '') $clean = 'upload_' . time();
    $clean = trim($clean);
    if ($clean === '' || $clean === '.' || $clean === '..') $clean = 'upload_' . time();
    return $clean;
}

function parse_size($v) {
    $v = trim((string)$v);
    if ($v === '') return PHP_INT_MAX;
    $unit = strtolower(substr($v, -1));
    $num = (int)$v;
    switch ($unit) {
        case 'g': return $num * 1024 * 1024 * 1024;
        case 'm': return $num * 1024 * 1024;
        case 'k': return $num * 1024;
        default:  return $num;
    }
}

function upload_file_url($name, $client = false) {
    $protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $host = $_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? 'localhost';
    $dir = rtrim(dirname($_SERVER['SCRIPT_NAME'] ?? '/api/verify.php'), '/');
    $url = "$protocol://$host$dir/verify.php?action=download_upload&name=" . rawurlencode($name);
    if ($client) {
        // 客户端直链: 不含 admin_token (App 下载时会自动附加会话凭证)
        return $url;
    }
    return $url . '&admin_token=' . rawurlencode(admin_token());
}

function list_uploads() {
    $dir = uploads_dir();
    $items = [];
    foreach ((glob($dir . '/*') ?: []) as $f) {
        if (!is_file($f)) continue;
        $items[] = [
            'name'        => basename($f),
            'size'        => filesize($f),
            'modified_at' => date('c', filemtime($f)),
        ];
    }
    usort($items, function ($a, $b) {
        return strcmp($b['modified_at'], $a['modified_at']);
    });
    return $items;
}

// ==================== 会话凭证校验 ====================
// App 卡密验证成功后持有 session_token = HMAC(card_key|uuid, secret)
// 返回 [是否有效, 失败原因]。config / download_upload 共用。
function app_session_check($cardKey, $uuid, $token) {
    if ($cardKey === '' || $uuid === '' || $token === '') {
        return [false, '缺少参数 (card_key/uuid/token)'];
    }
    $cards = load_cards();
    $idx = find_card_index($cards, $cardKey);
    if ($idx < 0) {
        return [false, '卡密不存在或已被删除'];
    }
    $card = $cards[$idx];
    $memberLevel  = (int)($card['member_level'] ?? 1);
    $isMemberCard = $memberLevel >= 1;
    $expireTs   = strtotime($card['expire_at'] ?? '');
    $notExpired = ($expireTs !== false && $expireTs >= time());
    // 会员卡: 必须设备匹配 (一机一码); 免费卡: 密码式, 不校验设备绑定
    $uuidMatch = $isMemberCard ? (!empty($card['uuid']) && $card['uuid'] === $uuid) : true;
    $tokenOk   = hash_equals(session_token($cardKey, $uuid), $token);
    if (!$notExpired) return [false, '卡密已过期'];
    if (!$uuidMatch)  return [false, '设备UUID不匹配(会员卡已绑定其他设备)'];
    if (!$tokenOk)    return [false, '会话token失效(需重新验证卡密)'];
    return [true, ''];
}

// ==================== Session Token (服务端强制管控) ====================
// 验证成功后下发的 token = HMAC(card_key|uuid, secret)
// 云控配置接口 (action=config) 必须携带有效 token 才返回完整按钮/下载直链
// 无 token / token 无效 / 卡密过期 / 设备不匹配 → 只返回锁定态基础信息
function app_secret() {
    static $secret = null;
    if ($secret !== null) return $secret;
    $f = data_file('app_secret.key');
    if (file_exists($f)) {
        $s = trim(file_get_contents($f));
        if ($s !== '') { $secret = $s; return $secret; }
    }
    $secret = bin2hex(random_bytes(24));
    @file_put_contents($f, $secret);
    return $secret;
}

function session_token($cardKey, $uuid) {
    return hash_hmac('sha256', $cardKey . '|' . $uuid, app_secret());
}

// ==================== 路由 ====================
$action = $_GET['action'] ?? '';

switch ($action) {

// -------------------- 诊断 --------------------
case 'health':
    $testFile = data_file('.write_test');
    $writeOk = @file_put_contents($testFile, 'ok') !== false;
    if ($writeOk) @unlink($testFile);
    out([
        'success'          => true,
        'php_version'      => PHP_VERSION,
        'data_dir'         => data_dir(),
        'data_dir_writable'=> $writeOk,
        'cards_file'       => file_exists(data_file('cards.json')),
        'settings_file'    => file_exists(data_file('settings.json')),
        'token_source'     => is_readable(__DIR__ . '/admin_token.txt') && trim((string)@file_get_contents(__DIR__ . '/admin_token.txt')) !== ''
                              ? 'admin_token.txt' : 'ADMIN_TOKEN constant',
        'token_is_default' => admin_token() === 'CHANGE_ME_TO_RANDOM_STRING',
    ]);
    break;

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

    $cards = load_cards();
    $idx = find_card_index($cards, $cardKey);
    if ($idx < 0) {
        out(['success' => false, 'message' => '卡密不存在']);
    }
    $card = $cards[$idx];
    $memberLevel = (int)($card['member_level'] ?? 1);   // 旧卡默认视为会员, 保持向后兼容
    $isMemberCard = $memberLevel >= 1;

    if ($isMemberCard) {
        // 会员卡: 一机一码, 首次激活绑定设备, 换设备需管理员解绑
        if (empty($card['uuid'])) {
            $cards[$idx]['uuid']           = $uuid;
            $cards[$idx]['activated_at']   = now_iso();
            save_cards($cards);
            $card = $cards[$idx];
        } elseif ($card['uuid'] !== $uuid) {
            out(['success' => false, 'message' => '该会员卡已绑定其他设备, 请联系管理员解绑']);
        }
        // 会员卡记录设备信息 (刷新机型/系统)
        $cards[$idx]['model']          = $model;
        $cards[$idx]['system_version'] = $sysVer;
        $cards[$idx]['system_name']    = $sysName;
        save_cards($cards);
    }
    // 免费卡: 密码式, 不绑定设备, 只校验卡密本身与有效期 (可多人共用)

    $expireTs = strtotime($card['expire_at'] ?? '');
    if ($expireTs === false || $expireTs < time()) {
        out(['success' => false, 'message' => '卡密已过期']);
    }

    out([
        'success'       => true,
        'message'       => '验证成功',
        'expire_at'     => date('c', $expireTs),
        'member_level'  => $memberLevel,
        'session_token' => session_token($cardKey, $uuid),
    ]);
    break;

// -------------------- App: 拉取云端配置 (带 session_token 鉴权) --------------------
case 'config':
    $cfg = load_config();
    // 自动填充接口地址
    if (empty($cfg['verify_server_url'])) {
        $protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
        $host = $_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? 'localhost';
        $script = $_SERVER['SCRIPT_NAME'] ?? '/api/verify.php';
        $cfg['verify_server_url'] = "$protocol://$host$script?action=verify";
    }
    if (empty($cfg['config_url'])) {
        $protocol = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
        $host = $_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? 'localhost';
        $script = $_SERVER['SCRIPT_NAME'] ?? '/api/verify.php';
        $cfg['config_url'] = "$protocol://$host$script?action=config";
    }
    $cfg['min_version'] = $cfg['min_version'] ?? '1.0.0';

    // ---- 鉴权: 必须携带卡密验证成功后下发的 session_token ----
    $cardKey = trim($_GET['card_key'] ?? '');
    $uuid    = trim($_GET['uuid'] ?? '');
    $token   = trim($_GET['token'] ?? '');
    [$authorized, $lockReason] = app_session_check($cardKey, $uuid, $token);

    header('Content-Type: application/json; charset=utf-8');
    if (!$authorized) {
        // 锁定态: 只下发基础信息, 功能配置全部置空
        // (破解版/未激活/被封卡密拿到的是空壳配置, 无任何可用功能)
        // locked_reason 仅供客户端诊断显示, 不泄露卡密/UUID 等敏感数据
        $locked = [
            'app_name'          => $cfg['app_name'],
            'version'           => $cfg['version'],
            'qq_group'          => $cfg['qq_group'],
            'wechat_official'   => $cfg['wechat_official'],
            'announcement'      => $cfg['announcement'],
            'config_url'        => $cfg['config_url'],
            'verify_server_url' => $cfg['verify_server_url'],
            'min_version'       => $cfg['min_version'],
            'locked'            => true,
            'locked_reason'     => $lockReason,
            'buttons'           => [],
            'member_buttons'    => [],
            'earphone_buttons'  => [],
            'download_shortcuts'=> [],
        ];
        echo json_encode($locked, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        exit;
    }

    $cfg['locked'] = false;
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

    $cards = load_cards();
    $existing = [];
    foreach ($cards as $c) $existing[$c['card_key'] ?? ''] = true;

    $generated = [];
    for ($i = 0; $i < $count; $i++) {
        $retries = 0;
        do {
            $key = gen_card_key();
            if (!isset($existing[$key])) {
                $existing[$key] = true;
                $cards[] = [
                    'card_key'       => $key,
                    'uuid'           => null,
                    'model'          => null,
                    'system_version' => null,
                    'system_name'    => null,
                    'member_level'   => $memberLevel,
                    'expire_at'      => $expireAt,
                    'activated_at'   => null,
                    'created_at'     => $now,
                    'note'           => $note,
                ];
                $generated[] = $key;
                break;
            }
            $retries++;
        } while ($retries < 5);
    }
    save_cards($cards);
    out(['success' => true, 'count' => count($generated), 'cards' => $generated, 'expire_at' => $expireAt, 'days' => $days]);
    break;

// -------------------- 管理: 列出卡密 --------------------
case 'list':
    check_admin();
    $search = trim($_GET['q'] ?? '');
    $onlyActive = ($_GET['active'] ?? '0') === '1';
    $cards = load_cards();
    $rows = [];
    foreach ($cards as $c) {
        if ($search !== '') {
            $hay = implode(' ', [$c['card_key'] ?? '', $c['uuid'] ?? '', $c['note'] ?? '']);
            if (mb_stripos($hay, $search) === false) continue;
        }
        if ($onlyActive && empty($c['uuid'])) continue;
        $c['expired']   = strtotime($c['expire_at'] ?? '') < time();
        $c['activated'] = !empty($c['uuid']);
        $rows[] = $c;
    }
    usort($rows, function ($a, $b) {
        return strcmp($b['created_at'] ?? '', $a['created_at'] ?? '');
    });
    out(['success' => true, 'count' => count($rows), 'cards' => $rows]);
    break;

// -------------------- 管理: 解绑 UUID --------------------
case 'unbind':
    check_admin();
    $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
    $cardKey = trim($body['card_key'] ?? '');
    if ($cardKey === '') out(['success' => false, 'message' => 'card_key 不能为空']);
    $cards = load_cards();
    $idx = find_card_index($cards, $cardKey);
    if ($idx < 0) out(['success' => false, 'message' => '卡密不存在']);
    $cards[$idx]['uuid'] = null;
    $cards[$idx]['model'] = null;
    $cards[$idx]['system_version'] = null;
    $cards[$idx]['system_name'] = null;
    $cards[$idx]['activated_at'] = null;
    save_cards($cards);
    out(['success' => true, 'message' => '已解绑设备']);
    break;

// -------------------- 管理: 续期 --------------------
case 'extend':
    check_admin();
    $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
    $cardKey = trim($body['card_key'] ?? '');
    $days = (int)($body['days'] ?? 30);
    if ($cardKey === '') out(['success' => false, 'message' => 'card_key 不能为空']);
    $cards = load_cards();
    $idx = find_card_index($cards, $cardKey);
    if ($idx < 0) out(['success' => false, 'message' => '卡密不存在']);
    $baseTs = strtotime($cards[$idx]['expire_at'] ?? '');
    $baseTs = ($baseTs !== false && $baseTs > time()) ? $baseTs : time();
    $newExpire = date('c', $baseTs + $days * 86400);
    $cards[$idx]['expire_at'] = $newExpire;
    save_cards($cards);
    out(['success' => true, 'message' => '续期成功', 'expire_at' => $newExpire]);
    break;

// -------------------- 管理: 删除卡密 --------------------
case 'delete':
    check_admin();
    $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
    $cardKey = trim($body['card_key'] ?? '');
    if ($cardKey === '') out(['success' => false, 'message' => 'card_key 不能为空']);
    $cards = load_cards();
    $idx = find_card_index($cards, $cardKey);
    if ($idx < 0) out(['success' => false, 'message' => '卡密不存在']);
    array_splice($cards, $idx, 1);
    save_cards($cards);
    out(['success' => true, 'message' => '已删除', 'affected' => 1]);
    break;

// -------------------- 管理: 统计 --------------------
case 'stats':
    check_admin();
    $cards = load_cards();
    $total = count($cards);
    $active = 0; $expired = 0;
    $now = time();
    foreach ($cards as $c) {
        if (!empty($c['uuid'])) $active++;
        $ts = strtotime($c['expire_at'] ?? '');
        if ($ts !== false && $ts < $now) $expired++;
    }
    out([
        'success' => true,
        'stats' => [
            'total'      => $total,
            'activated'  => $active,
            'unused'     => $total - $active,
            'valid'      => $total - $expired,
            'expired'    => $expired,
        ]
    ]);
    break;

// -------------------- 管理: 获取云控配置 --------------------
case 'get_config':
    check_admin();
    $cfg = load_config();
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
    @unlink(data_file('settings.json'));
    $cfg = default_config();
    file_put_contents(data_file('settings.json'), json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
    out(['success' => true, 'message' => '云控配置已重置为默认', 'config' => $cfg]);
    break;

// -------------------- 管理: 文件上传 --------------------
case 'upload':
    check_admin();

    if (!isset($_FILES['file'])) {
        out(['success' => false, 'message' => '未收到文件, 请使用 multipart/form-data, 字段名须为 file']);
    }
    $f = $_FILES['file'];
    if (!is_array($f) || !isset($f['error'])) {
        out(['success' => false, 'message' => '上传数据无效']);
    }
    if ($f['error'] !== UPLOAD_ERR_OK) {
        $map = [
            UPLOAD_ERR_INI_SIZE   => '文件超过服务器 upload_max_filesize 限制 (' . ini_get('upload_max_filesize') . ')',
            UPLOAD_ERR_FORM_SIZE  => '文件超过表单 MAX_FILE_SIZE 限制',
            UPLOAD_ERR_PARTIAL    => '文件只上传了一部分, 请重试',
            UPLOAD_ERR_NO_FILE    => '没有选择文件',
            UPLOAD_ERR_NO_TMP_DIR => '服务器缺少临时目录',
            UPLOAD_ERR_CANT_WRITE => '服务器无法写入文件',
            UPLOAD_ERR_EXTENSION  => '扩展阻止了上传',
        ];
        out(['success' => false, 'message' => $map[$f['error']] ?? ('上传失败 (错误码 ' . $f['error'] . ')')]);
    }
    if (($f['size'] ?? 0) <= 0) {
        out(['success' => false, 'message' => '文件为空']);
    }

    $name = sanitize_filename($f['name']);
    $dest = uploads_dir() . '/' . $name;
    // 重名时加序号, 避免覆盖
    if (file_exists($dest)) {
        $ext  = pathinfo($name, PATHINFO_EXTENSION);
        $base = ($ext !== '' && $ext !== $name) ? substr($name, 0, -strlen($ext) - 1) : $name;
        $i = 1;
        do {
            $name2 = $base . '_' . $i . ($ext !== '' ? '.' . $ext : '');
            $dest  = uploads_dir() . '/' . $name2;
            $i++;
        } while (file_exists($dest));
        $name = $name2;
    }

    if (!move_uploaded_file($f['tmp_name'], $dest)) {
        out(['success' => false, 'message' => '保存文件失败: 目录 ' . uploads_dir() . ' 可能不可写']);
    }

    out([
        'success' => true,
        'message' => '上传成功',
        'name'    => $name,
        'size'    => filesize($dest),
        'url'     => upload_file_url($name),
    ]);
    break;

// -------------------- 管理: 列出已上传文件 --------------------
case 'uploads':
    check_admin();
    $items = list_uploads();
    foreach ($items as &$it) {
        $it['url']        = upload_file_url($it['name']);           // 管理员直链 (含 admin_token, 仅自己测试用)
        $it['client_url'] = upload_file_url($it['name'], true);     // 客户端直链 (填到配置 download_url, App 自动带凭证)
    }
    unset($it);
    out([
        'success'    => true,
        'count'      => count($items),
        'files'      => $items,
        'uploads_dir'=> uploads_dir(),
        'upload_limit_hint' => '上传上限 ' . ini_get('upload_max_filesize') . ' / POST ' . ini_get('post_max_size'),
    ]);
    break;

// -------------------- 管理/客户端: 下载已上传文件 --------------------
// 双通道鉴权: 管理员 token 或 App 会话凭证 (card_key+uuid+token)。
// 客户端直链 (uploads 列表的 client_url) 不含 admin_token, App 下载时自动附加会话凭证。
case 'download_upload':
    $adminToken = $_GET['admin_token'] ?? $_SERVER['HTTP_X_ADMIN_TOKEN'] ?? '';
    $isAdmin = ($adminToken !== '' && hash_equals(admin_token(), $adminToken));
    if (!$isAdmin) {
        [$ok] = app_session_check(
            trim($_GET['card_key'] ?? ''),
            trim($_GET['uuid'] ?? ''),
            trim($_GET['token'] ?? '')
        );
        if (!$ok) {
            out(['success' => false, 'message' => '下载鉴权失败 (需管理员或有效会话凭证)'], 403);
        }
    }
    $name = $_GET['name'] ?? '';
    if (sanitize_filename($name) !== $name) {
        out(['success' => false, 'message' => '文件名非法'], 400);
    }
    $path = uploads_dir() . '/' . $name;
    if (!is_file($path)) {
        out(['success' => false, 'message' => '文件不存在'], 404);
    }
    header('Content-Type: application/octet-stream');
    header('Content-Disposition: attachment; filename="' . $name . '"');
    header('Content-Length: ' . filesize($path));
    readfile($path);
    exit;
    break;

// -------------------- 管理: 删除已上传文件 --------------------
case 'delete_upload':
    check_admin();
    $name = $_GET['name'] ?? '';
    if (sanitize_filename($name) !== $name) {
        out(['success' => false, 'message' => '文件名非法'], 400);
    }
    $path = uploads_dir() . '/' . $name;
    if (!is_file($path)) {
        out(['success' => false, 'message' => '文件不存在'], 404);
    }
    @unlink($path);
    out(['success' => true, 'message' => '已删除']);
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
<title>墨鱼Tool 管理后台</title>
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
  <div class="tab active" data-tab="cards" onclick="switchTab('cards')">🔑 卡密管理</div>
  <div class="tab" onclick="switchTab('config')" data-tab="config">☁️ 云控配置</div>
  <div class="tab" onclick="switchTab('upload')" data-tab="upload">📤 文件上传</div>
</div>
<div class="container">
<h1>墨鱼Tool 管理后台</h1>
<div class="notice">
  App 验证地址: <span class="mono" id="verify-url"></span><br>
  App 配置地址: <span class="mono" id="config-url"></span><br>
  认证方式: 同目录 <code>admin_token.txt</code> 内容优先, 否则用 <code>verify.php</code> 里的 <code>ADMIN_TOKEN</code> 常量。
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
      会员等级 <select id="gen-level"><option value="0">免费(不绑设备)</option><option value="1">会员(一机一码)</option><option value="2">耳机(一机一码)</option></select>
      备注 <input id="gen-note" placeholder="备注(可选)">
      <button onclick="genCard()">生成</button>
    </div>
    <div id="gen-result" class="mono" style="white-space:pre-wrap;background:#f9f9f9;padding:10px;border-radius:6px;margin-top:8px;display:none"></div>
  </div>
  <div class="card">
    <h3>📋 卡密列表 <button class="gray" onclick="printCards()" style="float:right">🖨️ 打印</button></h3>
    <div class="row">
      <input id="search" placeholder="搜索卡密/UUID/备注" onkeydown="if(event.key==='Enter')loadList()">
      <button onclick="loadList()">搜索</button>
      <label style="font-size:13px"><input type="checkbox" id="onlyActive"> 仅已激活</label>
      <button class="gray" onclick="loadList()">刷新</button>
    </div>
    <div style="overflow-x:auto">
      <table>
        <thead><tr>
          <th>卡密</th><th>UUID</th><th>设备</th><th>系统</th><th>等级</th><th>到期时间</th><th>激活时间</th><th>备注</th><th>状态</th><th>操作</th>
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
    <div class="row"><label style="min-width:110px">最低可用版本</label><input id="c-min_version" placeholder="低于此版本的 App 启动即锁定, 如 1.1.0"><span style="font-size:12px;color:#e67e22">版本封杀开关</span></div>
    <div class="row"><label style="min-width:110px">QQ 群</label><input id="c-qq_group"></div>
    <div class="row"><label style="min-width:110px">微信公众号</label><input id="c-wechat_official"></div>
    <div class="row"><label style="min-width:110px">验证服务器</label><input id="c-verify_server_url" placeholder="留空则自动用本接口"></div>
    <div class="row"><label style="min-width:110px">配置地址</label><input id="c-config_url" placeholder="留空则自动用本接口"></div>
    <div class="row" style="align-items:flex-start"><label style="min-width:110px">公告</label><textarea id="c-announcement" style="min-height:100px"></textarea></div>
  </div>

  <div class="card">
    <h3>🎨 外观主题</h3>
    <div class="row"><label style="min-width:110px">主色</label><input id="c-theme-primary" placeholder="#0A84FF"></div>
    <div class="row"><label style="min-width:110px">强调色</label><input id="c-theme-accent" placeholder="#3E434C"></div>
    <div class="row"><label style="min-width:110px">背景风格</label>
      <select id="c-theme-background">
        <option value="dark">深灰（默认）</option>
        <option value="light">明亮</option>
        <option value="aurora">深灰·经典(旧极光)</option>
      </select>
    </div>
    <div class="row"><label style="min-width:110px">圆角</label><input id="c-theme-corner_radius" type="number" value="16"></div>
    <div class="row"><label style="min-width:110px">按钮高度</label><input id="c-theme-button_height" type="number" value="54"></div>
    <div class="row"><label style="min-width:110px">字号缩放</label><input id="c-theme-font_scale" type="number" step="0.1" value="1.0"></div>
    <div class="row"><label style="min-width:110px">卡片透明度</label><input id="c-theme-card_opacity" type="number" step="0.05" value="0.85"></div>
  </div>

  <div class="card">
    <h3>🚨 急停开关</h3>
    <div class="row"><label style="min-width:110px">停用全体用户</label><input type="checkbox" id="c-kill_switch"></div>
    <div class="row"><label style="min-width:110px">停用文案</label><input id="c-kill_message" placeholder="服务已暂停，请联系管理员"></div>
  </div>

  <div class="card">
    <h3>🔀 备用线路</h3>
    <div class="row"><label style="min-width:110px">备用配置地址</label><input id="c-sources" placeholder="多个用英文逗号分隔，例如 http://ip2/api/verify.php?action=config,http://ip3/..."></div>
    <div style="font-size:12px;color:#888">主线路挂了会自动切换到备用线路，留空则只用主线路。</div>
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
    <h3>🎧 耳机按钮 <button class="gray" onclick="addButton('earphone_buttons')" style="float:right">+ 添加按钮</button></h3>
    <div id="c-earphone_buttons"></div>
    <div style="font-size:12px;color:#888">耳机档位（一机一码）专属按钮，仅 member_level=2 的卡密可见，会员和免费用户看不到。</div>
  </div>

  <div class="card">
    <h3>⬇️ 一键下载直链 <button class="gray" onclick="addShortcut()" style="float:right">+ 添加</button></h3>
    <div id="c-download_shortcuts"></div>
  </div>

  <div class="card">
    <h3>🖼️ 首页轮播图 <button class="gray" onclick="addBanner()" style="float:right">+ 添加</button></h3>
    <div id="c-banners"></div>
    <div style="font-size:12px;color:#888">image_url 为图片直链；link_url 点击跳转地址（可选，留空不跳转）；title 可留空。</div>
  </div>

  <div class="card">
    <h3>⚡ 自动美化（启动自动导入）</h3>
    <div class="row"><label style="min-width:110px">启用</label><input type="checkbox" id="c-auto_enabled"></div>
    <div class="row"><label style="min-width:110px">分类 ID</label><input id="c-auto_category_id" placeholder="如 beautify"></div>
    <div class="row"><label style="min-width:110px">配置包 ID</label><input id="c-auto_file_id" placeholder="如 mh_001（对应分类树 files[].id）"></div>
    <div style="font-size:12px;color:#888">App 启动并已获得文件权限后，自动下载该配置包导入对应目录；同包 24 小时内不重复。</div>
  </div>

  <div class="card">
    <h3>🗂️ 配置分类树（美化 / 画质 / 功能）</h3>
    <div style="font-size:12px;color:#888;margin-bottom:6px">
      结构为分类数组，每项含 id / title / type / icon / member_only / min_member_level / files。min_member_level：不设=按 member_only；1=会员及以上可见；2=仅耳机档位可见。files 每项字段：id、name、desc、download_url、target_dir（如 @game:paks）、unzip（true = zip 下载后自动解压导入包内文件）、size、version、icon。
    </div>
    <textarea id="c-raw-categories" style="min-height:260px"></textarea>
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

<!-- ============== Tab: 文件上传 ============== -->
<div id="tab-upload" class="config-section">
  <div class="card">
    <h3>📤 文件上传</h3>
    <div class="notice">
      上传文件到服务器（如 IPA 安装包），仅管理员可访问。<br>
      当前服务器上传限制：<b id="upload-limit">读取中…</b><br>
      <span style="font-size:12px;color:#e67e22">提示：若文件超过限制需在服务器 php.ini 调大 upload_max_filesize 与 post_max_size。</span>
    </div>
    <div class="row">
      <input type="file" id="upload-file" style="flex:1">
      <button class="green" onclick="uploadFile()">⬆️ 上传</button>
    </div>
    <div id="upload-progress" style="margin-top:8px;font-size:13px;color:#666"></div>
    <div id="upload-result" class="mono" style="white-space:pre-wrap;background:#f9f9f9;padding:10px;border-radius:6px;margin-top:8px;display:none"></div>
  </div>
  <div class="card">
    <h3>📁 已上传文件 <button class="gray" onclick="loadUploads()" style="float:right">↻ 刷新</button></h3>
    <div style="overflow-x:auto">
      <table>
        <thead><tr><th>文件名</th><th>大小</th><th>上传时间</th><th>操作</th></tr></thead>
        <tbody id="upload-list"></tbody>
      </table>
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
  document.querySelectorAll('.tab').forEach((t) => {
    t.classList.toggle('active', t.dataset.tab === name);
  });
  document.getElementById('tab-cards').classList.toggle('active', name === 'cards');
  document.getElementById('tab-config').classList.toggle('active', name === 'config');
  document.getElementById('tab-upload').classList.toggle('active', name === 'upload');
  if (name === 'config' && CURRENT_CONFIG === null) loadConfig();
  if (name === 'upload') loadUploads();
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

// member_level 数字 → 档位名
function levelName(lv) {
  if (lv >= 2) return '耳机';
  if (lv >= 1) return '会员';
  return '免费';
}
// 档位名 → tag 样式
function levelTag(lv) {
  if (lv >= 2) return '<span class="tag" style="background:#e8d5ff;color:#6a1fb0">耳机</span>';
  if (lv >= 1) return '<span class="tag blue">会员</span>';
  return '<span class="tag gray">免费</span>';
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
    tbody.innerHTML = '<tr><td colspan="10" style="text-align:center;color:#999;padding:20px">无数据</td></tr>';
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
      <td>${levelTag(c.member_level)}</td>
      <td>${fmtDate(c.expire_at)}</td>
      <td>${c.activated_at ? fmtDate(c.activated_at) : '-'}</td>
      <td style="max-width:120px;overflow:hidden;text-overflow:ellipsis">${esc(c.note) || '-'}</td>
      <td>${statusTag}</td>
      <td>${actions.join('')}</td>`;
    tbody.appendChild(tr);
  }
}

// 打印全部卡密: 弹出可打印视图, 包含卡密/等级/到期/激活/UUID/设备/备注/状态
function printCards() {
  const rows = document.querySelectorAll('#card-list tr');
  if (rows.length === 0 || rows[0].querySelector('td[colspan]')) { alert('没有数据'); return; }
  let html = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><title>卡密列表</title>
  <style>
    body { font-family: "PingFang SC", sans-serif; padding: 20px; }
    h1 { text-align: center; font-size: 20px; margin-bottom: 8px; }
    .info { text-align: center; font-size: 12px; color: #888; margin-bottom: 16px; }
    table { width: 100%; border-collapse: collapse; font-size: 11px; }
    th, td { border: 1px solid #ccc; padding: 4px 6px; text-align: left; }
    th { background: #f0f0f0; font-weight: 600; }
    .mono { font-family: Menlo, monospace; font-size: 10px; }
  </style></head><body>
  <h1>墨鱼Tool 卡密列表</h1>
  <div class="info">打印时间: ${new Date().toLocaleString('zh-CN')}</div>
  <table><thead><tr>
    <th>卡密</th><th>档位</th><th>状态</th><th>到期时间</th><th>激活时间</th><th>绑定设备(UUID)</th><th>设备型号</th><th>系统版本</th><th>备注</th>
  </tr></thead><tbody>`;
  rows.forEach(tr => {
    const tds = tr.querySelectorAll('td');
    const key = tds[0].textContent;
    const uuid = tds[1].textContent;
    const model = tds[2].textContent;
    const sys = tds[3].textContent;
    const level = tds[4].textContent;
    const expire = tds[5].textContent;
    const activated = tds[6].textContent;
    const note = tds[7].textContent;
    const status = tds[8].textContent;
    html += `<tr><td class="mono">${key}</td><td>${level}</td><td>${status}</td><td>${expire}</td><td>${activated}</td><td class="mono">${uuid}</td><td>${model}</td><td>${sys}</td><td>${note}</td></tr>`;
  });
  html += '</tbody></table></body></html>';
  const w = window.open('', '_blank');
  w.document.write(html);
  w.document.close();
  setTimeout(() => w.print(), 500);
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
  document.getElementById('c-min_version').value = cfg.min_version ?? '1.0.0';
  document.getElementById('c-qq_group').value = cfg.qq_group ?? '';
  document.getElementById('c-wechat_official').value = cfg.wechat_official ?? '';
  document.getElementById('c-verify_server_url').value = cfg.verify_server_url ?? '';
  document.getElementById('c-config_url').value = cfg.config_url ?? '';
  document.getElementById('c-announcement').value = cfg.announcement ?? '';
  renderButtons('buttons', cfg.buttons ?? []);
  renderButtons('member_buttons', cfg.member_buttons ?? []);
  renderButtons('earphone_buttons', cfg.earphone_buttons ?? []);
  renderShortcuts(cfg.download_shortcuts ?? []);
  renderBanners(cfg.banners ?? []);
  document.getElementById('c-auto_enabled').checked = !!(cfg.auto_beautify && cfg.auto_beautify.enabled);
  document.getElementById('c-auto_category_id').value = (cfg.auto_beautify && cfg.auto_beautify.category_id) || '';
  document.getElementById('c-auto_file_id').value = (cfg.auto_beautify && cfg.auto_beautify.file_id) || '';
  document.getElementById('c-raw-categories').value = JSON.stringify(cfg.categories ?? [], null, 2);
}

function collectConfig() {
  // 以最近一次加载的完整配置为基底, 只覆盖表单可编辑字段,
  // 避免丢失 theme / kill_switch / sources / game_dirs 等表单未编辑字段
  const cfg = JSON.parse(JSON.stringify(CURRENT_CONFIG || {}));
  cfg.app_name = document.getElementById('c-app_name').value;
  cfg.version = document.getElementById('c-version').value;
  cfg.min_version = document.getElementById('c-min_version').value || '1.0.0';
  cfg.qq_group = document.getElementById('c-qq_group').value;
  cfg.wechat_official = document.getElementById('c-wechat_official').value;
  cfg.verify_server_url = document.getElementById('c-verify_server_url').value;
  cfg.config_url = document.getElementById('c-config_url').value;
  cfg.announcement = document.getElementById('c-announcement').value;
  cfg.buttons = collectButtons('buttons');
  cfg.member_buttons = collectButtons('member_buttons');
  cfg.earphone_buttons = collectButtons('earphone_buttons');
  cfg.download_shortcuts = collectShortcuts();
  cfg.banners = collectBanners();
  cfg.auto_beautify = {
    enabled: document.getElementById('c-auto_enabled').checked,
    category_id: document.getElementById('c-auto_category_id').value.trim(),
    file_id: document.getElementById('c-auto_file_id').value.trim()
  };
  const catStr = document.getElementById('c-raw-categories').value.trim();
  if (catStr) {
    try { cfg.categories = JSON.parse(catStr); }
    catch (e) { throw new Error('分类树 JSON 无效: ' + e.message); }
  }
  return cfg;
}

const ACTIONS = ['open_file_manager','download','run_script','open_url','update_url','announcement','uninstall','game_diagnostic','custom'];

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
        <label style="font-size:12px">最低等级
          <select data-f="min_member_level" style="max-width:150px;padding:4px 8px">
            <option value="" ${b.min_member_level == null ? 'selected' : ''}>默认(按会员开关)</option>
            <option value="1" ${b.min_member_level === 1 ? 'selected' : ''}>会员及以上</option>
            <option value="2" ${b.min_member_level === 2 ? 'selected' : ''}>仅耳机</option>
          </select>
        </label>
      </div>
      <div class="row">
        <input placeholder="path 跳转目录（支持 @game:paks）" value="${esc(b.path ?? '')}" data-f="path">
      </div>
      <div class="row">
        <input placeholder="target_dir 下载目录（支持 @game:paks）" value="${esc(b.params?.target_dir ?? '')}" data-f="target_dir">
        <label style="font-size:12px;white-space:nowrap"><input type="checkbox" data-f="unzip" ${b.unzip ? 'checked' : ''}> 解压导入</label>
      </div>
      <div class="row">
        <input placeholder="confirm_text 二次确认文案" value="${esc(b.confirm_text ?? '')}" data-f="confirm_text">
      </div>
      <div class="row">
        <input placeholder="paths 逗号分隔 (uninstall 用)" value="${esc((b.paths ?? []).join(', '))}" data-f="paths">
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
    const ml = item.querySelector('[data-f="min_member_level"]').value;
    if (ml !== '') b.min_member_level = parseInt(ml);
    const path = item.querySelector('[data-f="path"]').value; if (path) b.path = path;
    const targetDir = item.querySelector('[data-f="target_dir"]').value; if (targetDir) b.params = { target_dir: targetDir };
    if (item.querySelector('[data-f="unzip"]').checked) b.unzip = true;
    const confirmText = item.querySelector('[data-f="confirm_text"]').value; if (confirmText) b.confirm_text = confirmText;
    const pathsRaw = item.querySelector('[data-f="paths"]').value;
    const paths = pathsRaw.split(',').map(s => s.trim()).filter(s => s);
    if (paths.length) b.paths = paths;
    out.push(b);
  });
  return out;
}

function addButton(fieldId) {
  const cfg = CURRENT_CONFIG || {};
  cfg[fieldId] = cfg[fieldId] || [];
  cfg[fieldId].push({ title: '新按钮', action: 'open_file_manager', color: '#FF6B9D', member_only: fieldId === 'member_buttons', min_member_level: fieldId === 'earphone_buttons' ? 2 : undefined });
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

function renderBanners(arr) {
  const container = document.getElementById('c-banners');
  container.innerHTML = '';
  (arr || []).forEach((b, idx) => {
    const div = document.createElement('div');
    div.className = 'btn-array-item';
    div.innerHTML = `
      <div class="row">
        <input placeholder="图片直链 image_url" value="${esc(b.image_url ?? '')}" data-f="image_url" style="flex:2">
        <button class="gray" onclick="removeBanner(this)">✕</button>
      </div>
      <div class="row"><input placeholder="点击跳转 link_url (可选)" value="${esc(b.link_url ?? '')}" data-f="link_url"></div>
      <div class="row"><input placeholder="标题 title (可选)" value="${esc(b.title ?? '')}" data-f="title"></div>
    `;
    container.appendChild(div);
  });
}

function collectBanners() {
  const container = document.getElementById('c-banners');
  const items = container.querySelectorAll('.btn-array-item');
  const out = [];
  items.forEach(item => {
    out.push({
      image_url: item.querySelector('[data-f="image_url"]').value,
      link_url: item.querySelector('[data-f="link_url"]').value || null,
      title: item.querySelector('[data-f="title"]').value || null
    });
  });
  return out;
}

function addBanner() {
  CURRENT_CONFIG = CURRENT_CONFIG || {};
  CURRENT_CONFIG.banners = CURRENT_CONFIG.banners || [];
  CURRENT_CONFIG.banners.push({ image_url: '', link_url: '', title: '' });
  renderBanners(CURRENT_CONFIG.banners);
}

function removeBanner(btn) {
  if (!confirm('确定删除此轮播图?')) return;
  const item = btn.closest('.btn-array-item');
  const container = document.getElementById('c-banners');
  const idx = Array.from(container.children).indexOf(item);
  CURRENT_CONFIG.banners.splice(idx, 1);
  renderBanners(CURRENT_CONFIG.banners);
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

// ==================== 文件上传 ====================
function fmtSize(n) {
  if (n == null) return '-';
  if (n < 1024) return n + ' B';
  if (n < 1024 * 1024) return (n / 1024).toFixed(1) + ' KB';
  if (n < 1024 * 1024 * 1024) return (n / 1024 / 1024).toFixed(2) + ' MB';
  return (n / 1024 / 1024 / 1024).toFixed(2) + ' GB';
}

async function loadUploads() {
  const r = await api('uploads');
  const limitEl = document.getElementById('upload-limit');
  if (r.upload_limit_hint) limitEl.textContent = r.upload_limit_hint;
  const tbody = document.getElementById('upload-list');
  tbody.innerHTML = '';
  if (!r.success) { alert(r.message); return; }
  if (!r.files || r.files.length === 0) {
    tbody.innerHTML = '<tr><td colspan="4" style="text-align:center;color:#999;padding:20px">暂无文件</td></tr>';
    return;
  }
  for (const f of r.files) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="mono">${esc(f.name)}</td>
      <td>${fmtSize(f.size)}</td>
      <td>${fmtDate(f.modified_at)}</td>
      <td style="white-space:nowrap;max-width:420px">
        <a class="tag blue" href="${esc(f.url)}" target="_blank" style="text-decoration:none">下载</a>
        <button class="gray" onclick="copyText('${esc(f.client_url)}');this.textContent='已复制'">客户端直链</button>
        <button class="gray" onclick="deleteUpload('${esc(f.name)}')">删除</button>
        <div class="mono" style="font-size:11px;color:#999;margin-top:4px;word-break:break-all">${esc(f.client_url)}</div>
      </td>`;
    tbody.appendChild(tr);
  }
}

function copyText(t) {
  (navigator.clipboard ? navigator.clipboard.writeText(t) : Promise.reject())
    .catch(() => {
      const ta = document.createElement('textarea');
      ta.value = t; document.body.appendChild(ta); ta.select();
      document.execCommand('copy'); ta.remove();
    });
}

async function uploadFile() {
  const input = document.getElementById('upload-file');
  const file = input.files[0];
  if (!file) { alert('请先选择文件'); return; }
  const prog = document.getElementById('upload-progress');
  const res = document.getElementById('upload-result');
  prog.textContent = '上传中… ' + file.name + ' (' + fmtSize(file.size) + ')';
  const url = API_BASE + '?action=upload&' + tok().slice(1);
  const fd = new FormData();
  fd.append('file', file);
  try {
    const resp = await fetch(url, { method: 'POST', body: fd });
    const r = await resp.json();
    if (!r.success) {
      prog.textContent = '';
      res.textContent = '上传失败: ' + (r.message || '未知错误');
      res.style.color = 'red';
      res.style.display = 'block';
      return;
    }
    prog.textContent = '';
    res.style.color = '';
    res.textContent = '✅ 上传成功\n文件名: ' + r.name + '\n大小: ' + fmtSize(r.size) + '\n下载地址: ' + r.url;
    res.style.display = 'block';
    input.value = '';
    loadUploads();
  } catch (e) {
    prog.textContent = '';
    res.textContent = '上传出错: ' + e.message;
    res.style.color = 'red';
    res.style.display = 'block';
  }
}

async function deleteUpload(name) {
  if (!confirm('确定删除 ' + name + ' ?')) return;
  const url = API_BASE + '?action=delete_upload&name=' + encodeURIComponent(name) + '&' + tok().slice(1);
  const r = await (await fetch(url)).json();
  alert(r.message); loadUploads();
}
</script>
</body>
</html>
    <?php
    break;

default:
    out(['success' => false, 'message' => '未知 action: ' . htmlspecialchars($action)]);
}
