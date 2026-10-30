    // 空闲心跳：helper 在 status 过期后会显示自带兜底文案，定期补发以顶掉它
    if (heartbeatTimer) clearInterval(heartbeatTimer)
    lastHostEventAt = Date.now()
    heartbeatTimer = setInterval(() => {
      if (!bridge) return
      // 粘滞到期后必须恢复：放在活跃判断之前，否则活跃时永远恢复不了
      if (wechatRestorePending && Date.now() >= wechatStickyUntil) {
        wechatRestorePending = false
        if (lastReducerState) {
          try {
            bridge.send(lastReducerState)
          } catch {}
        } else {
          sendOverrideState({
            state: CompanionState.IDLE,
            phase: 'idle-keepalive',
            stage: '等待任务',
            message: '小月姬在这儿等你哦',
            detail: 'DSH · 等待下一次任务',
          })
        }
        return
      }
      // 活跃会话优先：DSH 正在跑任务时不抢状态
      if (Date.now() - lastHostEventAt < 5000) return
      if (Date.now() < wechatStickyUntil) {
        renderWechatNotice('有人给你发微信了，快去看看吧')
        return
      }
      sendOverrideState({
        state: CompanionState.IDLE,
        phase: 'idle-keepalive',
        stage: '等待任务',
        message: '小月姬在这儿等你哦',
        detail: 'DSH · 等待下一次任务',
      })
    }, 3000)
    heartbeatTimer.unref?.()
    startWechatWatch()
