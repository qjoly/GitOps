// GitHub pane: token-gated live view of PRs, mentions and repo activity, refreshed on a timer.
import { Button, Input, SegmentedControl, haptic, host, useQuery, queryClient, useValue, atom } from '@hermes/plugin-sdk'
import { useState } from 'react'
import { jsx, jsxs } from 'react/jsx-runtime'

const ID = 'github-pane'
const REFRESH_MS = 3 * 60 * 1000

// Plugin-scoped settings (token, watched repos) live in one atom so every pane instance agrees.
const prefs = atom({ token: '', repos: ['Qjoly/GitOps'] })
const ready = atom(false)
const visible = atom(false)
let ctxRef = null

const save = (next) => {
  prefs.set(next)
  if (ctxRef) void ctxRef.storage.set('prefs', next)
}

const repoPath = (full) => full.split('/').map(encodeURIComponent).join('/')

const rel = (iso) => {
  if (!iso) return ''
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return 'now'
  if (s < 3600) return Math.floor(s / 60) + 'm'
  if (s < 86400) return Math.floor(s / 3600) + 'h'
  return Math.floor(s / 86400) + 'd'
}

const api = async (token, path) => {
  const res = await fetch('https://api.github.com' + path, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: 'Bearer ' + token,
      'X-GitHub-Api-Version': '2022-11-28'
    }
  })
  if (res.status === 401) throw new Error('token rejected (401)')
  if (res.status === 403) throw new Error('rate limit or scope (403)')
  if (!res.ok) throw new Error('GitHub ' + res.status)
  return res.json()
}

const open = (url) => {
  if (host.openExternal) void host.openExternal(url)
  else window.open(url, '_blank', 'noopener')
}

async function load(tab, token, repos, me, repo) {
  if (tab === 'inbox') {
    const data = await api(token, '/issues?filter=assigned&state=open&per_page=50')
    return { items: data.map(normalize) }
  }
  if (tab === 'review') {
    const data = await api(token, '/pulls?state=open&per_page=100&sort=updated')
    return {
      items: data
        .filter((p) => (p.requested_reviewers || []).some((r) => r.login === me)
          || (p.requested_teams || []).length > 0)
        .map((p) => ({ id: p.id, title: p.title, url: p.html_url, sub: repo + ' #' + p.number + ' · ' + rel(p.updated_at), kind: p.draft ? 'draft' : 'pr' }))
    }
  }
  if (tab === 'notifs') {
    const data = await api(token, '/notifications?all=false&per_page=50')
    return {
      items: data.map((n) => ({
        id: n.id, title: n.subject.title, url: htmlUrl(n),
        sub: n.repository.full_name + ' · ' + (n.reason || '') + ' · ' + rel(n.updated_at),
        kind: n.subject.type === 'PullRequest' ? 'pr' : 'issue'
      }))
    }
  }
  const out = []
  for (const full of repos.slice(0, 3)) {
    const [commits, runs] = await Promise.all([
      api(token, '/repos/' + repoPath(full) + '/commits?per_page=4'),
      api(token, '/repos/' + repoPath(full) + '/actions/runs?per_page=3')
    ])
    out.push({
      full,
      commits: commits.map((c) => ({
        sha: c.sha.slice(0, 7), msg: c.commit.message.split('\n')[0],
        url: c.html_url, when: c.commit.author.date
      })),
      runs: runs.workflow_runs.map((r) => ({
        name: r.name, branch: r.head_branch, status: r.status, conclusion: r.conclusion, url: r.html_url
      }))
    })
  }
  return { repos: out }
}

const htmlUrl = (n) => {
  const api = n.subject.url || ''
  const rest = api.replace('https://api.github.com/repos/', '')
  const issue = /\/pulls\/(\d+)$/.exec(rest)
  const repo = n.repository.full_name
  if (issue) return 'https://github.com/' + repo + '/pull/' + issue[1]
  const num = /\/issues\/(\d+)$/.exec(rest)
  return num ? 'https://github.com/' + repo + '/issues/' + num[1] : n.repository.html_url
}

const normalize = (i) => ({
  id: i.id, title: i.title, url: i.html_url,
  sub: ((i.repository_url || '').split('/repos/')[1] || '') + ' #' + i.number + ' · ' + rel(i.updated_at),
  kind: i.pull_request ? (i.draft ? 'draft' : 'pr') : 'issue'
})

function Row({ item }) {
  return jsxs('button', {
    type: 'button',
    onClick: () => { haptic('tap'); open(item.url) },
    className: 'flex w-full items-start gap-2 px-2 py-1.5 text-left text-[0.75rem] leading-snug hover:bg-(--chrome-action-hover)',
    children: [
      jsx('span', { className: 'shrink-0 pt-px text-(--ui-text-quaternary)', children: item.kind === 'pr' ? '⇄' : item.kind === 'draft' ? '◌' : '◉' }),
      jsxs('span', { className: 'min-w-0 flex-1', children: [
        jsx('span', { className: 'block truncate text-foreground', children: item.title }),
        jsx('span', { className: 'block truncate text-(--ui-text-quaternary)', children: item.sub })
      ] })
    ]
  })
}

function Repo({ repo }) {
  return jsxs('div', { className: 'border-b border-(--ui-stroke-secondary) px-1 py-1.5 last:border-0', children: [
    jsx('div', { className: 'flex items-center justify-between px-1 pb-1 text-[0.6875rem] font-medium text-(--ui-text-tertiary)', children: [
      jsx('span', { children: repo.full }),
      jsx('button', {
        type: 'button',
        className: 'text-(--ui-text-quaternary) hover:text-foreground',
        onClick: () => open('https://github.com/' + repo.full),
        children: 'open'
      })
    ] }),
    ...repo.commits.map((c) => jsxs('button', {
      type: 'button',
      key: c.sha,
      onClick: () => open(c.url),
      className: 'flex w-full items-baseline gap-2 px-1 py-0.5 text-left text-[0.72rem] hover:bg-(--chrome-action-hover)',
      children: [
        jsx('span', { className: 'shrink-0 font-mono text-(--ui-text-quaternary)', children: c.sha }),
        jsx('span', { className: 'min-w-0 flex-1 truncate text-foreground', children: c.msg }),
        jsx('span', { className: 'shrink-0 text-(--ui-text-quaternary)', children: rel(c.when) })
      ]
    })),
    ...repo.runs.map((r) => jsxs('button', {
      type: 'button',
      key: r.url,
      onClick: () => open(r.url),
      className: 'flex w-full items-baseline gap-2 px-1 py-0.5 text-left text-[0.72rem] hover:bg-(--chrome-action-hover)',
      children: [
        jsx('span', {
          className: 'shrink-0 font-mono ' + (r.status !== 'completed' ? 'text-amber-500' : r.conclusion === 'success' ? 'text-emerald-500' : 'text-red-500'),
          children: r.status !== 'completed' ? '●' : r.conclusion === 'success' ? '✓' : '✕'
        }),
        jsx('span', { className: 'min-w-0 flex-1 truncate text-(--ui-text-tertiary)', children: r.name + ' · ' + r.branch })
      ]
    }))
  ] })
}

function Settings({ onSaved }) {
  const p = useValue(prefs)
  const [token, setToken] = useState('')
  const [repos, setRepos] = useState(p.repos.join(', '))
  return jsxs('div', { className: 'flex h-full flex-col gap-3 overflow-auto p-3 text-xs', children: [
    jsx('div', { className: 'text-(--ui-text-tertiary)', children: 'Read-only GitHub token (classic, scope repo + notifications). Stored locally in this plugin.' }),
    jsx(Input, { type: 'password', placeholder: 'ghp_…', value: token, onChange: (e) => setToken(e.target.value) }),
    jsx('div', { className: 'text-(--ui-text-tertiary)', children: 'Watched repositories (comma separated, max 3)' }),
    jsx(Input, { value: repos, onChange: (e) => setRepos(e.target.value) }),
    jsxs('div', { className: 'flex gap-2', children: [
      jsx(Button, {
        variant: 'outline',
        onClick: () => {
          save({
            token: (token || prefs.get().token).trim(),
            repos: repos.split(',').map((s) => s.trim()).filter(Boolean)
          })
          setToken('')
          queryClient.invalidateQueries({ queryKey: [ID] })
          onSaved()
        },
        children: p.token ? 'Update' : 'Save'
      }),
      p.token ? jsx(Button, {
        variant: 'ghost',
        onClick: () => { save({ ...p, token: '' }); onSaved() },
        children: 'Forget token'
      }) : null
    ] })
  ] })
}

function Pane() {
  const p = useValue(prefs)
  const isReady = useValue(ready)
  const onScreen = useValue(visible)
  const [tab, setTab] = useState('inbox')
  const [settingsOpen, setSettingsOpen] = useState(false)
  const showSettings = settingsOpen || !p.token
  const token = p.token

  const query = useQuery({
    queryKey: [ID, tab, token.slice(-6), p.repos.join(',')],
    enabled: Boolean(token) && isReady && !showSettings,
    retry: false,
    refetchInterval: onScreen ? REFRESH_MS : false,
    staleTime: 30_000,
    queryFn: async () => {
      const me = (await api(token, '/user')).login
      return load(tab, token, p.repos, me, p.repos[0] || '')
    }
  })

  if (!isReady) return jsx('div', { className: 'p-3 text-xs text-(--ui-text-tertiary)', children: 'loading…' })
  if (showSettings) {
    return jsx(Settings, { onSaved: () => setSettingsOpen(false) })
  }

  const data = query.data
  const items = (data && data.items) || []
  const err = query.error

  return jsxs('div', { className: 'flex h-full min-h-0 flex-col text-xs', children: [
    jsxs('div', { className: 'flex items-center gap-1 border-b border-(--ui-stroke-secondary) px-2 py-1.5', children: [
      jsx(SegmentedControl, {
        value: tab,
        onChange: (v) => setTab(v),
        options: [
          { value: 'inbox', label: 'Assigned' },
          { value: 'review', label: 'Review' },
          { value: 'notifs', label: 'Notifs' },
          { value: 'repos', label: 'Repos' }
        ].map((o) => ({ value: o.value, label: jsx('span', { className: 'text-[0.6875rem]', children: o.label }) }))
      }),
      jsx('span', { className: 'flex-1' }),
      jsx('button', {
        type: 'button',
        title: 'Refresh',
        className: 'px-1 text-(--ui-text-quaternary) hover:text-foreground',
        onClick: () => { haptic('tap'); queryClient.invalidateQueries({ queryKey: [ID] }) },
        children: query.isFetching ? '…' : '↻'
      }),
      jsx('button', {
        type: 'button',
        title: 'Settings',
        className: 'px-1 text-(--ui-text-quaternary) hover:text-foreground',
        onClick: () => setSettingsOpen(true),
        children: '⚙'
      })
    ] }),
    jsxs('div', { className: 'min-h-0 flex-1 overflow-auto', children: [
      err ? jsx('div', { className: 'p-3 text-red-500', children: String(err.message || err) }) : null,
      !err && query.isPending ? jsx('div', { className: 'p-3 text-(--ui-text-tertiary)', children: 'loading…' }) : null,
      !err && data && tab === 'repos' ? (data.repos || []).map((r) => jsx(Repo, { repo: r }, r.full)) : null,
      !err && data && tab !== 'repos' ? (items.length
        ? items.map((i) => jsx(Row, { item: i }, i.id))
        : jsx('div', { className: 'p-3 text-(--ui-text-tertiary)', children: 'nothing open' })) : null
    ] })
  ] })
}

export default {
  id: ID,
  name: 'GitHub Pane',
  register(ctx) {
    ctxRef = ctx
    // Poll only while the pane is on screen (older hosts without paneVisibility always poll).
    if (typeof host.paneVisibility === 'function') {
      const vis = host.paneVisibility(ID + ':gh')
      visible.set(Boolean(vis.get()))
      const off = vis.subscribe((v) => visible.set(Boolean(v)))
      ctx.onDispose(off)
    } else visible.set(true)
    void ctx.storage.get('prefs').then((stored) => {
      if (stored && typeof stored === 'object' && typeof stored.token === 'string') {
        prefs.set({ token: stored.token, repos: Array.isArray(stored.repos) && stored.repos.length ? stored.repos : ['Qjoly/GitOps'] })
      }
      ready.set(true)
    })
    ctx.register({
      id: 'gh',
      area: 'panes',
      title: 'github',
      data: { placement: 'right', width: '300px' },
      render: () => jsx(Pane, {})
    })
  }
}
