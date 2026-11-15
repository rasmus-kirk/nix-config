# Chat module

`kirk.llmModules.chat` runs local models in Ollama and the Open WebUI chat.
Ollama listens on `127.0.0.1:11434`. Open WebUI listens on port 8080 on all
interfaces, and the firewall opens the port.

## Options

- `models` lists the models that Open WebUI offers. The first model is the
  default. At boot, Ollama downloads each model that has no entry in
  `modelfiles`.
- `modelfiles` maps a model name to a base model (`from`) and Modelfile
  lines (`settings`). At boot, `ollama-modelfiles.service` downloads the
  base model and runs `ollama create`.
- `contextLength` sets the context window of each model. The default is
  32768 tokens.
- `port` sets the Open WebUI port.
- `tailscaleServe` serves Open WebUI at `https://<host>.<tailnet>.ts.net`
  through Tailscale Serve. Port 8080 stays open on the LAN.

## Tailscale

`open-webui-tailscale-serve.service` runs `tailscale serve`, which forwards
`https://<host>.<tailnet>.ts.net` to Open WebUI. Only devices on the tailnet
reach it. Tailscale gets the certificate from Let's Encrypt, so the host
name appears in the public Certificate Transparency logs.

Before the first start, turn on HTTPS Certificates on the DNS page of the
Tailscale admin console (<https://login.tailscale.com/admin/dns>). Until
then, the service fails and retries every few seconds.

## Model

The default model is `qwen3.6-heretic:35b`. It is
[Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) with the
refusals removed by [Heretic](https://github.com/p-e-w/heretic), from
[llmfan46/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-GGUF](https://huggingface.co/llmfan46/Qwen3.6-35B-A3B-uncensored-heretic-Native-MTP-Preserved-GGUF).
The model card reports these results:

- Refusals drop from 83/100 to 10/100.
- The KL divergence from the original model is 0.0015. KL divergence
  measures how far the answers drift from the original. 0 means identical.

Heretic removes refusals only. Topics that Qwen's training data slants stay
slanted.

The model uses 3B of its 35B parameters per token, so it stays fast when part
of it is in system RAM. It keeps the multi-token prediction (MTP) layers,
which guess the next tokens so that each step produces more than one token.

The Hugging Face file brings its own chat template. The Modelfile replaces
it with Ollama's built-in Qwen renderer and parser and the sampling
parameters of Ollama's `qwen3.6:35b`. Thinking and tool calls then work the
same way as in `qwen3.6:35b`.

Open WebUI shows only the models in `models` (`OLLAMA_API_CONFIGS`), so the
Hugging Face base model stays out of the model menu. Every approved account
sees these models (`BYPASS_MODEL_ACCESS_CONTROL=True`). Without that setting,
Open WebUI shows a model to normal accounts only after an admin grants
access to it in Admin Settings.

## First start

1. Open `http://desktop:8080`.
2. Create an account. The first account becomes the admin.
3. Sign out and create a second account to chat from.
4. Sign in as the admin and approve the second account in Admin Panel >
   Users.

Every account after the first starts as pending until the admin approves
it.

## Settings

Open WebUI reads its settings from Nix at every start
(`ENABLE_PERSISTENT_CONFIG=False`). A change in Admin Settings lasts until
the next restart.

## Chats

Normal accounts chat in temporary chats only. Open WebUI keeps temporary
chats out of its database and hides the Save button. Admins can still save
chats, so chat from a normal account.

The memory tools are off (`ENABLE_MEMORIES=False`), so the model stores
nothing about you between chats.

## GPU

`services.ollama.package` defaults to `pkgs.ollama-vulkan`. Vulkan can see
the Intel iGPU as well as the Radeon. To see the GPUs that Ollama uses, run:

```sh
journalctl -u ollama | grep 'inference compute'
```

If the Radeon is missing, set `services.ollama.package = pkgs.ollama-rocm;`.
ROCm sees only AMD GPUs. Some cards also need
`services.ollama.rocmOverrideGfx`.

## posthog overlay

The module includes an overlay for `python3Packages.posthog`. Open WebUI
needs posthog through chromadb, and the pinned nixpkgs marks posthog broken.
`docs/ideas/drop-posthog-overlay.md` describes when to delete the overlay.
