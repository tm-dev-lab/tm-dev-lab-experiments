package com.tmdevlab.bank.web;

import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;

/**
 * Simulates a downstream I/O call (database, network) by parking the request thread for a fixed
 * delay. This is what makes the workload I/O-bound rather than CPU-bound: threads block instead of
 * spinning, so throughput is limited by concurrency and the JVM is free to be judged on memory and
 * GC behavior. Actuator endpoints are exempt so health/metrics stay fast.
 */
@Component
public class IoLatencyFilter implements Filter {

    private final long delayMs;

    public IoLatencyFilter(@Value("${bank.io-delay-ms:5}") long delayMs) {
        this.delayMs = delayMs;
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        if (delayMs > 0
                && request instanceof HttpServletRequest http
                && !http.getRequestURI().startsWith("/actuator")) {
            try {
                Thread.sleep(delayMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        chain.doFilter(request, response);
    }
}
