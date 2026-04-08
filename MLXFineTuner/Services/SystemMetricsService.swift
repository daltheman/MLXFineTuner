import Foundation
import Darwin
import IOKit

// MARK: - Data model

struct SystemMetrics {
    var cpuPercent:  Double = 0     // 0–100
    var memUsedGB:   Double = 0
    var memTotalGB:  Double = 0
    var gpuPercent:  Double? = nil  // nil when unavailable

    var memPercent: Double {
        guard memTotalGB > 0 else { return 0 }
        return (memUsedGB / memTotalGB) * 100.0
    }
}

// MARK: - Service

/// Samples CPU, RAM, and GPU usage. Call `sample()` repeatedly; the first
/// CPU reading will be 0 (it needs two samples to diff the tick counters).
final class SystemMetricsService {

    // MARK: CPU state

    private struct CPUTicks {
        var user:   UInt32 = 0
        var system: UInt32 = 0
        var idle:   UInt32 = 0
        var nice:   UInt32 = 0
    }
    private var lastTicks: CPUTicks?

    // MARK: Memory total (read once, cached)

    private lazy var totalMemGB: Double = {
        var mem: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &mem, &len, nil, 0)
        return Double(mem) / (1024 * 1024 * 1024)
    }()

    // MARK: - Public

    func sample() -> SystemMetrics {
        SystemMetrics(
            cpuPercent: sampleCPU(),
            memUsedGB:  sampleMemUsed(),
            memTotalGB: totalMemGB,
            gpuPercent: sampleGPU()
        )
    }

    // MARK: - CPU

    private func sampleCPU() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfoPtr: processor_info_array_t?
        var numInfo: mach_msg_type_number_t = 0

        guard host_processor_info(mach_host_self(),
                                   PROCESSOR_CPU_LOAD_INFO,
                                   &numCPUs,
                                   &cpuInfoPtr,
                                   &numInfo) == KERN_SUCCESS,
              let info = cpuInfoPtr else { return 0 }

        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(numInfo))
        }

        var user: UInt32 = 0, sys: UInt32 = 0
        var idle: UInt32 = 0, nice: UInt32 = 0
        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(numCPUs) {
            user += UInt32(bitPattern: Int32(info[stride * i + Int(CPU_STATE_USER)]))
            sys  += UInt32(bitPattern: Int32(info[stride * i + Int(CPU_STATE_SYSTEM)]))
            idle += UInt32(bitPattern: Int32(info[stride * i + Int(CPU_STATE_IDLE)]))
            nice += UInt32(bitPattern: Int32(info[stride * i + Int(CPU_STATE_NICE)]))
        }

        let current = CPUTicks(user: user, system: sys, idle: idle, nice: nice)

        guard let prev = lastTicks else {
            lastTicks = current
            return 0
        }
        lastTicks = current

        let dUser  = Double(current.user   &- prev.user)
        let dSys   = Double(current.system &- prev.system)
        let dIdle  = Double(current.idle   &- prev.idle)
        let dNice  = Double(current.nice   &- prev.nice)
        let dTotal = dUser + dSys + dIdle + dNice

        guard dTotal > 0 else { return 0 }
        return min(100, (dUser + dSys + dNice) / dTotal * 100.0)
    }

    // MARK: - Memory

    private func sampleMemUsed() -> Double {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let ret = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard ret == KERN_SUCCESS else { return 0 }

        let page      = Double(vm_kernel_page_size)
        let wired     = Double(stats.wire_count)            * page
        let active    = Double(stats.active_count)          * page
        let compress  = Double(stats.compressor_page_count) * page
        return (wired + active + compress) / (1024 * 1024 * 1024)
    }

    // MARK: - GPU (via IOAccelerator / Apple Silicon AGX)

    private func sampleGPU() -> Double? {
        let matching = IOServiceMatching("IOAccelerator")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }

            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef,
                                                 kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let props = propsRef?.takeRetainedValue() as? [String: Any],
               let perf  = props["PerformanceStatistics"] as? [String: Any],
               let util  = perf["Device Utilization %"] as? Double {
                return min(100, util)
            }

            service = IOIteratorNext(iter)
        }
        return nil
    }
}
