:net_kernel.start([:manager, :shortnames])

Application.ensure_all_started(:singleton)

ExUnit.start()
