# Apple Watch companion safety checkpoint

- Full verified checkpoint: `195ffef`
- Checkpoint branch: `codex/watch-offline-checkpoint-20260808`
- Watch-only rollback commit: `93d4f7c`
- Rollback branch: `codex/watch-companion-rollback`

The rollback removes only the native Watch app, WatchConnectivity file
transfer, and the corresponding Flutter sync hook. It preserves the phone
essay, grammar, listening, TTS, sentence navigation, and five-second media
control changes.

The rollback state passed all 130 non-Watch Flutter tests before the patch was
created.

Preferred rollback command from the checkpoint branch or a descendant:

```sh
git cherry-pick 93d4f7c
```

The standalone patch in this directory can be used instead:

```sh
git am docs/checkpoints/0001-rollback-remove-optional-Apple-Watch-companion.patch
```

