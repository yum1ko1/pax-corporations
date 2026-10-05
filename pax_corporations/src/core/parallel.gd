extends RefCounted
## Data-parallel loops on the engine's worker threads (WorkerThreadPool).
## for_each(count, fn) calls fn(from, to) on chunks of [0, count) in parallel and WAITS for all of them, so
## the main thread (UI, map layer, game) never reads the data while workers write it.
## Rules for fn: touch only items from..to-1 (each company's own dictionaries), read shared data only,
## no game / Pax / node calls, no shared caches (pre-fill them on the main thread), own RNG per chunk.

const MIN_ITEMS := 64        # below this the thread hand-off costs more than it saves
const ITEMS_PER_CHUNK := 24

static var enabled := true
static var threads_used := 0   # chunks of the last parallel run (for «corp bench» and Pax Optimize)


static func for_each(count: int, fn: Callable) -> void:
	if count <= 0:
		return
	var workers := maxi(1, OS.get_processor_count() - 1)
	var off := Engine.has_meta(&"pax_threads") and not bool(Engine.get_meta(&"pax_threads"))   # Pax Corptimizer's switch
	if not enabled or off or count < MIN_ITEMS or workers < 2:
		threads_used = 1
		fn.call(0, count)
		return
	var chunks := clampi(ceili(float(count) / ITEMS_PER_CHUNK), 2, workers * 2)
	var size := ceili(float(count) / chunks)
	threads_used = chunks
	var chunk := func(i: int) -> void:
		var from := i * size
		if from < count:
			fn.call(from, mini(count, from + size))
	var task := WorkerThreadPool.add_group_task(chunk, chunks, -1, true, "pax_corporations")
	WorkerThreadPool.wait_for_group_task_completion(task)
