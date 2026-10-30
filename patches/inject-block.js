  // ── 小月姬定制补丁（patch_pet.py 注入，勿手改）────────────────────────────
  const LOW_BALANCE_YUAN = Number(process.env.DSH_YUEYJI_LOW_BALANCE ?? 5)
  let lowBalanceActive = false
  let lastWechatNoticeAt = 0
  let lastSessionProbeAt = 0
  let lastHostEventAt = 0
  let heartbeatTimer

  const sendOverrideState = (payload) => {
    if (!bridge) return
    try {
      bridge.send(createMessage(CompanionMessageKind.STATE, payload))
    } catch {}
  }

  const balanceAmount = (snapshot) => {
    const rows = Array.isArray(snapshot?.balances) ? snapshot.balances : []
    const row = rows.find((r) => r && r.currency === 'CNY') ?? rows[0]
    const total = Number(row?.total)
    return Number.isFinite(total) ? total : null
  }

  const announceLowBalance = (snapshot) => {
    const total = balanceAmount(snapshot)
    if (total === null) return
    const low = total < LOW_BALANCE_YUAN
    if (low === lowBalanceActive) return
    lowBalanceActive = low
    if (low) {
      sendOverrideState({
        state: CompanionState.ERROR,
        phase: 'balance-low',
        stage: '余额不足',
        message: `余额只剩 ${total.toFixed(2)} 元了…我没力气了`,
        detail: '记得充值，我在这儿等你',
      })
    } else {
      sendOverrideState({
        state: CompanionState.IDLE,
        phase: 'balance-ok',
        stage: '等待任务',
        message: '余额回来啦，我又有力气了！',
        detail: 'DSH · 等待下一次任务',
      })
    }
  }

  const sessionHaystack = (session) => {
    const header = session?.header ?? {}
    return [header.id, header.title, header.name, header.label, header.cwd,
      header.agentPreset, session?.id]
      .filter((value) => typeof value === 'string').join(' | ')
  }

  const announceWechatMessage = (session, event) => {
    if (!event || event.type !== 'user/message') return
    const hay = sessionHaystack(session)
    try {
      if (Date.now() - lastSessionProbeAt > 30000) {
        lastSessionProbeAt = Date.now()
        diagnosticsLog.write('INFO', `session probe: ${hay}`)
      }
    } catch {}
    if (!/(channel-wechat|wechat|微信)/i.test(hay)) return
    const now = Date.now()
    if (now - lastWechatNoticeAt < 3000) return
    lastWechatNoticeAt = now
    // helper 在有任务卡时优先渲染任务卡，会盖掉 STATE 文案；
    // 先清空任务卡再推 STATE，气泡才会显示微信提示。
    const flash = () => {
      if (!bridge) return
      try {
        bridge.send(createMessage(CompanionMessageKind.TASKS, { tasks: [] }))
      } catch {}
      sendOverrideState({
        state: CompanionState.WAITING,
        phase: 'wechat-inbound',
        stage: '微信消息',
        message: '微信有新消息！',
        detail: '快看看是谁找我～',
      })
    }
    flash()
    try {
      setTimeout(flash, 800).unref?.()
    } catch {}
  }
  const WECHAT_DB_ROOT = process.env.DSH_YUEYJI_WECHAT_DB ?? 'D:/xwechat_files'
  const WECHAT_QUIET_MS = 45000
  const WECHAT_STICKY_MS = 20000
  let wechatStickyUntil = 0
  let wechatRestorePending = false
  let lastReducerState = null
  let wechatDbBaseline = null
  let lastWechatDbNoticeAt = 0
  let wechatWatchTimer

  const newestWechatDbMtime = () => {
    let newest = 0
    try {
      for (const entry of readdirSync(WECHAT_DB_ROOT, { withFileTypes: true })) {
        if (!entry.isDirectory() || !entry.name.startsWith('wxid_')) continue
        const msgDir = join(WECHAT_DB_ROOT, entry.name, 'db_storage', 'message')
        let names
        try {
          names = readdirSync(msgDir)
        } catch {
          continue
        }
        for (const name of names) {
          if (!/^message_.*\.db(?:-(?:wal|shm))?$/.test(name)) continue
          try {
            const stamp = statSync(join(msgDir, name)).mtimeMs
            if (stamp > newest) newest = stamp
          } catch {}
        }
      }
    } catch {}
    return newest
  }

  const renderWechatNotice = (detail) => {
    if (!bridge) return
    try {
      bridge.send(createMessage(CompanionMessageKind.TASKS, { tasks: [] }))
    } catch {}
    sendOverrideState({
      state: CompanionState.WAITING,
      phase: 'wechat-db',
      stage: '微信消息',
      message: '微信有人找你！',
      detail,
    })
  }

  // 首次推送才续期；心跳续推走 renderWechatNotice，避免无限延长
  const pushWechatNotice = (detail) => {
    wechatStickyUntil = Date.now() + WECHAT_STICKY_MS
    wechatRestorePending = true
    renderWechatNotice(detail)
  }

  const startWechatWatch = () => {
    if (wechatWatchTimer) clearInterval(wechatWatchTimer)
    wechatDbBaseline = newestWechatDbMtime()
    if (!wechatDbBaseline) {
      diagnosticsLog.write('INFO', `wechat watch disabled: no message db under ${WECHAT_DB_ROOT}`)
      return
    }
    diagnosticsLog.write('INFO', `wechat watch armed: ${WECHAT_DB_ROOT}`)
    wechatWatchTimer = setInterval(() => {
      const newest = newestWechatDbMtime()
      if (!newest || newest <= wechatDbBaseline) return
      wechatDbBaseline = newest
      const now = Date.now()
      if (now - newest > 20000) return
      if (now - lastWechatDbNoticeAt < WECHAT_QUIET_MS) return
      lastWechatDbNoticeAt = now
      pushWechatNotice('有人给你发微信了，快去看看吧')
    }, 4000)
    wechatWatchTimer.unref?.()
  }

  // ── 定制补丁结束 ────────────────────────────────────────────────────────

