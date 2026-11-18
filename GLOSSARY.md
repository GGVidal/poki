# Poki Glossary

Poki is an iPhone assistant that operates the phone on its owner's behalf, paired with desktop tools that install it and let external agents control the device. This glossary defines each product concept once so code, documentation, issues, and agents use consistent terminology.

## Products

**Poki**:
The personal assistant that operates the owner's iPhone, and the name of the overall product suite.
_Related_: Poki app, Poki MCP
_Avoid_: the bot, the robot

**Poki app**:
The iPhone app where the owner chats with Poki and where Poki completes tasks across other apps without needing a computer.
_Related_: Poki Runner, Conversation
_Avoid_: iOS app, client, phone agent

**Poki Runner**:
The companion app that enables Poki to control third-party apps on iPhones where the Poki app cannot act alone.
_Related_: Automation session, Poki app
_Avoid_: runner app, test runner, automation helper

**Poki Setup**:
The Mac and Windows application that installs the Poki app on an iPhone and renews its Apple signature.
_Related_: Pairing, Renewal
_Avoid_: installer, setup app, desktop app

**Poki MCP**:
The local computer service that lets MCP clients, such as coding agents, view and control a connected iPhone or simulator.
_Related_: External agent, Device lease
_Avoid_: daemon, MCP server, bridge

**Poki Agent**:
The standalone terminal agent on a computer that can also respond through messaging channels.
_Related_: Messaging channel, Poki MCP
_Avoid_: CLI agent, terminal Poki

## Working on the iPhone

**Task**:
A single unit of work that the owner or an agent asks Poki to complete, such as ordering lunch or replying to a message.
_Related_: Step, Conversation
_Avoid_: job, request, command, to-do

**Step**:
A single action Poki performs within a task, such as tapping a button, entering text, or opening an app.
_Related_: Task, Approval
_Avoid_: move, operation

**Conversation**:
A message thread between the owner and Poki, including all tasks executed within that thread.
_Related_: Task
_Avoid_: session, chat thread

**Sensitive step**:
A step that makes a payment, deletes data, sends a message, places a call, enters a password, or interacts with Wallet.
_Related_: Approval, Takeover
_Avoid_: dangerous action, risky step

**Approval**:
The owner's explicit decision to allow or block a sensitive step before Poki performs it.
_Related_: Sensitive step, Auto-classifier, Operator approval
_Avoid_: confirmation, permission, consent

**Auto-classifier**:
An optional setting that lets the owner's chat model handle approvals on their behalf using a Permissive, Balanced, or Strict preset.
_Related_: Approval, Activity log
_Avoid_: approval mode, auto-approve, AI approver

**Takeover**:
When the owner reclaims control of the iPhone from Poki during an active task. The owner can hand back control when ready for Poki to continue.
_Related_: Hand back, Sensitive step
_Avoid_: handoff, interrupt, pause

**Hand back**:
Returning control of the iPhone to Poki after a takeover so the task continues from where it paused.
_Related_: Takeover
_Avoid_: resume, give back

**Automation session**:
The active period during which Poki controls the iPhone to interact with other apps, indicated by a system banner in iOS.
_Related_: Poki Runner, Step
_Avoid_: session, test session

**App capsule**:
An inline badge displaying an app's icon and name whenever Poki mentions that app in text.
_Related_: Conversation
_Avoid_: pill, chip, app tag

**Result card**:
A structured native card in a conversation that presents task outcomes, such as flight options, rather than plain text.
_Related_: Task, Suggestion card
_Avoid_: rich reply, widget

**Suggestion card**:
A proactive card Poki displays when a habit is due. It offers the usual action, a few alternatives, and a text field so the owner can start the task with one tap.
_Related_: Habit, Result card
_Avoid_: choice card, nudge, popup

## Memory

**Memory library**:
Everything Poki keeps about its owner on the iPhone, including memories, skills, habits, to-dos, and Your people. Every agent operating the phone shares this library.
_Related_: Memory, Skill, Habit, Memory page
_Avoid_: memory store, brain, knowledge base

**Memory**:
A single detail Poki remembers about the owner's preferences or personal context, such as dietary restrictions or a home address. Each memory is either global or tagged with a specific app.
_Related_: Global memory, App memory, Memory library
_Avoid_: note, fact, preference entry

**Global memory**:
A memory without an app tag that Poki applies across all tasks. Global memories appear under About You on the Memory page.
_Related_: App memory, Rule
_Avoid_: always-on memory, core memory, permanent memory

**App memory**:
A memory tagged with a specific app that Poki applies only when working inside that app.
_Related_: App tag, Global memory
_Avoid_: app note, app preference

**App tag**:
The specific app associated with a memory, skill, or habit.
_Related_: App memory, Skill
_Avoid_: app label, category

**Rule**:
A locked global or app memory created by the owner that instructs Poki to always or never perform a specific behavior.
_Related_: Locked, Global memory
_Avoid_: policy, setting

**Skill**:
A reusable procedure for one task in one app, saved after Poki completes that task, so Poki can repeat it in one go next time.
_Related_: App tag, Habit, Agent skill
_Avoid_: routine, flow, workflow, playbook, macro

**Agent skill**:
A packaged instruction set that teaches an external coding agent how to install or operate Poki. It belongs to the external agent rather than the on-device Memory library.
_Related_: Skill, External agent
_Avoid_: Poki skill, skill (on its own, when Skill could be meant)

**Habit**:
A recurring action the owner takes around the same time in a specific app, linked to the supporting skill, relevant memories, and the reason Poki identified it.
_Related_: Skill, Suggestion card, Reason, Behavior log
_Avoid_: routine, pattern, schedule

**To-do**:
Something the owner has agreed to do, phrased as one sentence from the owner's side with a due time, which Poki reminds the owner about when it is due.
_Related_: Your people, Screen observation
_Avoid_: task, reminder, commitment

**Your people**:
The people the owner refers to by name or relationship, such as "Mom", each linked to a contact with an address, a birthday, and the app the owner usually uses to reach them.
_Related_: Memory library, To-do
_Avoid_: contacts, relationships, social graph

**Source**:
How a memory, habit, or to-do was created or updated, whether stated directly by the owner, learned during a conversation, discovered in the nightly review, or edited manually.
_Related_: Reason, Locked
_Avoid_: origin, provenance

**Reason**:
The supporting evidence Poki displays for a habit or learned memory to show why Poki inferred it.
_Related_: Habit, Source
_Avoid_: basis, justification, explanation

**Locked**:
The protected status of any item added or edited by the owner, allowing Poki to read the item while preventing automatic edits or merges.
_Related_: Rule, Source
_Avoid_: pinned, protected, frozen

**Recent updates**:
A view on the Memory page listing the latest items Poki learned or modified, accessible by tapping "Memory updated" in a conversation.
_Related_: Memory page, Nightly review
_Avoid_: changelog, history, activity

**Memory page**:
The dedicated screen in the Poki app where the owner views, edits, and deletes saved context, organized with About You at the top followed by individual apps.
_Related_: Memory library, Recent updates
_Avoid_: notes page, memory list

**Nightly review**:
An automated maintenance pass that runs overnight while the iPhone charges, analyzing the behavior log and recent tasks to add, update, or remove memories, habits, and skills.
_Related_: Behavior log, Habit, Recent updates
_Avoid_: consolidation, background review, sync

**Screen history**:
A private, PIN-protected on-device log recording which apps appeared on screen and when.
_Related_: Screen observation, Behavior log
_Avoid_: activity log, screen recording, timeline

**Screen observation**:
The background feature where Poki observes on-screen activity while the owner uses other apps, automatically ignoring excluded apps.
_Related_: Screen history, Excluded apps
_Avoid_: monitoring, surveillance, tracking

**Excluded apps**:
Apps omitted from screen observation to protect sensitive information, such as password managers, banking apps, and payment tools.
_Related_: Screen observation
_Avoid_: blocklist, private apps

**Behavior log**:
A concise daily summary distilled from screen history that captures when the owner used an app and what they did inside it.
_Related_: Screen history, Nightly review, Habit
_Avoid_: activity log, usage log, screen history

**Activity log**:
The chronological record of actions taken by agents on the iPhone and how each approval was resolved.
_Related_: Approval, Step
_Avoid_: behavior log, screen history, audit log

## Agents and connections

**External agent**:
An agent running outside the Poki app, such as a desktop coding agent, that controls the iPhone through Poki.
_Related_: Connector, Guest, Poki MCP
_Avoid_: outside agent, client, third-party agent

**Guest**:
An external agent while it is operating the iPhone, shown to the owner so they can stop it at any time.
_Related_: External agent, Takeover
_Avoid_: visitor, remote user

**Connector**:
The unique connection address an external agent uses to reach the iPhone through the owner's relay.
_Related_: Relay, External agent
_Avoid_: endpoint, MCP URL, integration

**Relay**:
A forwarding service on the internet, deployed by the owner, that routes requests from external agents to the iPhone when the phone is away from the computer.
_Related_: Connector, Local connection
_Avoid_: proxy, tunnel, cloud server

**Local connection**:
The VPN app on the iPhone that lets the Poki app communicate with automation services running on the same iPhone.
_Related_: Loopback, Relay
_Avoid_: VPN, tunnel, proxy app

**Loopback**:
The local network route established by the local connection back to the iPhone itself. Poki requires an active loopback to tap and type.
_Related_: Local connection
_Avoid_: localhost, VPN

**Voice bridge**:
A lightweight Mac utility that issues short-lived credentials for live voice sessions so the iPhone never stores persistent voice API keys.
_Related_: Poki app
_Avoid_: voice server, voice relay

## Computer side

**Pairing**:
The USB trust relationship established between a computer and an iPhone, required before Poki Setup or Poki MCP can communicate with the device.
_Related_: Poki Setup, Poki MCP
_Avoid_: linking, binding, trust

**Signing**:
The Apple code signature that authorizes the Poki app to run on an iPhone. Signatures created with a free Apple Account expire after seven days.
_Related_: Renewal, Poki Setup
_Avoid_: certificate, provisioning

**Renewal**:
Re-applying the Apple code signature to an installed Poki app before the current signature expires.
_Related_: Signing, Poki Setup
_Avoid_: refresh, re-sign, reinstall

**Release channel**:
The line of builds a Poki installation follows for updates, such as Beta.
_Related_: Poki Setup
_Avoid_: channel (on its own), track, ring

**Messaging channel**:
An external chat platform, such as iMessage or Telegram, that the owner uses to communicate with Poki Agent.
_Related_: Poki Agent
_Avoid_: channel (on its own), gateway, provider

**Device lease**:
Exclusive control of an iPhone or simulator granted to a single MCP session so multiple agents do not conflict.
_Related_: Poki MCP, External agent
_Avoid_: lock, reservation, claim

**Operator approval**:
Explicit confirmation given by the user at the computer before Poki MCP performs sensitive host or device actions, such as installing apps, opening links, or reading the clipboard.
_Related_: Approval, Poki MCP
_Avoid_: approval (on its own), permission
