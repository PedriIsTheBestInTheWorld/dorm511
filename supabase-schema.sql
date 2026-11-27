-- 511宿舍公务系统 — Supabase 建表脚本
-- 用法：在 Supabase 控制台打开 SQL Editor，整段粘贴进去点 Run。
-- 全部 8 张表：id 一律 uuid 主键（默认 gen_random_uuid()），
-- created_at 一律 timestamptz（默认 now()）。
--
-- 行级安全（RLS）说明：下面对每张表都执行了 disable row level security。
-- 这是刻意为之，不是漏写——宿舍内互信，所有人用同一个 anon key 读写，
-- 公开程度和以前 LeanCloud 的 App Key 一致。
-- anon key 本来就是公开密钥（设计如此），不要把 service_role key 放进 App。
-- 如果以后想收紧（比如只有维护者能改功德），再到 Supabase 里开 RLS 写策略。

create extension if not exists pgcrypto;

-- 成员：昵称、床位、功德、哈夫币
create table if not exists members (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  bed text not null default '',
  merit int not null default 0,
  coins int not null default 0
);

-- 宿舍公告
create table if not exists notices (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  title text not null,
  content text not null default '',
  author text not null default ''
);

-- 职位：名字、现任者、上任时间（since 是 '2026-11-27' 这样的文本日期）
create table if not exists offices (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  holder text not null default '空缺',
  since text not null default ''
);

-- 投票：标题、类型（general / appointment）、选项（jsonb 数组）、状态（open / closed）
-- office_id：任命类投票才填，指向被任命的职位；created_by：发起人昵称
create table if not exists polls (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  title text not null,
  type text not null default 'general',
  options jsonb not null default '[]'::jsonb,
  status text not null default 'open',
  office_id uuid references offices (id) on delete set null,
  created_by text not null default ''
);

-- 投票记录：一人一票（poll_id + voter 唯一），option 是选项下标（0 起）
create table if not exists votes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  poll_id uuid not null references polls (id) on delete cascade,
  voter text not null,
  option int not null default 0
);
create unique index if not exists votes_poll_voter_unique
  on votes (poll_id, voter);

-- 宿舍群聊
create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  sender text not null,
  content text not null default ''
);

-- 维护记录：功德 / 哈夫币变动、任命、改名
-- kind：merit / coins / appoint / rename；amount：变动数（任命、改名填 0）
create table if not exists ledger (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  kind text not null,
  member text not null,
  amount int not null default 0,
  note text not null default '',
  by text not null default ''
);

-- 通用键值表：目前只存维护密码（key = 'maintainer_pin'，value = 4 位数字）
create table if not exists meta (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  key text not null unique,
  value text not null default ''
);

-- 关掉行级安全（见文件头说明）。
alter table members disable row level security;
alter table notices disable row level security;
alter table offices disable row level security;
alter table polls disable row level security;
alter table votes disable row level security;
alter table chat_messages disable row level security;
alter table ledger disable row level security;
alter table meta disable row level security;
