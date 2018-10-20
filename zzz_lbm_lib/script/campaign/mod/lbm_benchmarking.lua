local benchmarking = {}

local function noop()
end

local function noop_fixture_func(func)
    func()
end

function benchmarking.new_suite(max_time, max_iters, check_time_every_n_iters)
    if type(max_time) == "table" then
        local opts = max_time
        return benchmarking.new_suite(opts.max_time, opts.max_iters, opts.check_time_every_n_iters)
    end
    local self = {
        max_time = max_time,
        max_iters = max_iters,
        check_time_every_n_iters = check_time_every_n_iters,
        control_name = "control (only benchmarking overhead)",
        control_func = noop,
        control_fixture_func = noop_fixture_func,
        names = {}, -- for ordering the benchmarks in the suite
        funcs = {},
        fixture_funcs = {},
    }
    setmetatable(self, {__index = benchmarking})
    return self
end

function benchmarking:set_control(name, func, fixture_func)
    self.control_name = name
    self.control_func_name = func
    self.control_fixture_func = fixture_func or noop_fixture_func
end

function benchmarking:add(name, func, fixture_func)
    self.names[#self.names + 1] = name
    self.funcs[name] = func
    self.fixture_funcs[name] = fixture_func or noop_fixture_func
end

local function run_benchmark(max_time, max_iters, check_time_every_n_iters, name, func, fixture_func, control_time_per_iter)
    collectgarbage()
    collectgarbage() -- 2nd collectgarbage finalizes objects used in any gc finalizers
    local time_elapsed = 0 -- in seconds
    local num_iters = max_iters
    local outer_max_iters = max_iters / check_time_every_n_iters
    fixture_func(function(...)
        local start_time = os.clock()
        for i = 1, outer_max_iters do
            for _ = 1, check_time_every_n_iters do
                func(...)
            end
            time_elapsed = os.clock() - start_time
            if time_elapsed > max_time then
                num_iters = i * check_time_every_n_iters
                break
            end
        end
    end)
    local time_per_iter = time_elapsed / num_iters * 1000000000 -- in nanoseconds
    if control_time_per_iter == nil then
        control_time_per_iter = time_per_iter
    end
    out(string.format("%-50s|%14d |%12.3fs |%12.3fns |%12.3fns", name, num_iters, time_elapsed, time_per_iter, time_per_iter - control_time_per_iter))
    collectgarbage()
    collectgarbage() -- 2nd collectgarbage finalizes objects used in any gc finalizers
    return {
        num_iters = num_iters,
        time_elapsed = time_elapsed,
        time_per_iter = time_per_iter,
    }
end

function benchmarking:run_control()
    return run_benchmark(self.max_time, self.max_iters, self.check_time_every_n_iters, self.control_name, self.control_func, self.control_fixture_func, nil)
end

function benchmarking:run(name, control_time_per_iter)
    return run_benchmark(self.max_time, self.max_iters, self.check_time_every_n_iters, name, self.funcs[name], self.fixture_funcs[name], control_time_per_iter)
end

function benchmarking:run_suite()
    out("BENCHMARKS")
    out("----------")
    out("NAME                                              | # ITERS       | TIME ELAPSED  | TIME PER ITER | MINUS CONTROL")
    out("-----------------------------------------------------------------------------------------------------------------")
    local control_record = self:run_control(self.control_name)
    local records = {[self.control_name] = control_record}
    for _, name in ipairs(self.names) do
        records[name] = self:run(name, control_record.time_per_iter)
    end
    out("-----------------------------------------------------------------------------------------------------------------")
    return records
end

function benchmarking:aggregate_results(suite_results)
    local num_suite_results = #suite_results
    local control_name = self.control_name
    local names = {control_name, unpack(self.names)}
    
    local aggregate_records = {}
    for _, name in ipairs(names) do
        local aggregate_record = {
            num_iters = 0,
            time_elapsed = 0,
            mean_time_per_iter = 0,
        }
        aggregate_records[name] = aggregate_record
    end
    for _, records in ipairs(suite_results) do
        for _, name in ipairs(names) do
            local record = records[name]
            local aggregate_record = aggregate_records[name]
            aggregate_record.num_iters = aggregate_record.num_iters + record.num_iters
            aggregate_record.time_elapsed = aggregate_record.time_elapsed + record.time_elapsed
            aggregate_record.mean_time_per_iter = aggregate_record.mean_time_per_iter + record.time_per_iter / num_suite_results
        end
    end
    
    out("BENCHMARKS AGGREGATE")
    out("--------------------")
    out("NAME                                              | # ITERS       | TIME ELAPSED  | TIME PER ITER | MINUS CONTROL | AVG TIME PER ITER | MINUS AVG CONTROL")
    out("---------------------------------------------------------------------------------------------------------------------------------------------------------")
    local aggregate_control_record = aggregate_records[control_name]
    local aggregate_control_time_per_iter = aggregate_control_record.time_elapsed / aggregate_control_record.num_iters * 1000000000 -- in nanoseconds
    for _, name in ipairs(names) do
        local aggregate_record = aggregate_records[name]
        local aggregate_time_per_iter = aggregate_record.time_elapsed / aggregate_record.num_iters * 1000000000 -- in nanoseconds
        out(string.format("%-50s|%14d |%12.3fs |%12.3fns |%12.3fns |%16.3fns |%16.3fns", name,
            aggregate_record.num_iters, aggregate_record.time_elapsed,
            aggregate_time_per_iter, aggregate_time_per_iter - aggregate_control_time_per_iter,
            aggregate_record.mean_time_per_iter, aggregate_record.mean_time_per_iter - aggregate_control_record.mean_time_per_iter))
    end
    out("---------------------------------------------------------------------------------------------------------------------------------------------------------")
    return aggregate_records
end

return benchmarking
