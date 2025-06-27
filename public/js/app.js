// Kea DHCP Manager JavaScript

// Global application state
window.KeaDhcpApp = {
    statusUpdateInterval: null,
    autoRefreshEnabled: true,
    refreshInterval: 30000 // 30 seconds
};

// Initialize application when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    initializeApp();
    setupGlobalEventListeners();
    startAutoRefresh();
});

// Application initialization
function initializeApp() {
    console.log('Kea DHCP Manager initialized');
    
    // Set active navigation item
    setActiveNavigation();
    
    // Initialize tooltips
    initializeTooltips();
    
    // Setup form validation
    setupFormValidation();
    
    // Initialize data tables if present
    initializeDataTables();
}

// Set active navigation item based on current URL
function setActiveNavigation() {
    const currentPath = window.location.pathname;
    const navLinks = document.querySelectorAll('.navbar-nav .nav-link');
    
    navLinks.forEach(link => {
        link.classList.remove('active');
        if (link.getAttribute('href') === currentPath) {
            link.classList.add('active');
        }
    });
}

// Initialize Bootstrap tooltips
function initializeTooltips() {
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltipTriggerList.map(function(tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });
}

// Setup global event listeners
function setupGlobalEventListeners() {
    // Handle form submissions with loading states
    document.addEventListener('submit', function(e) {
        const form = e.target;
        if (form.tagName === 'FORM') {
            showFormLoading(form);
        }
    });
    
    // Handle AJAX form submissions
    document.addEventListener('click', function(e) {
        if (e.target.classList.contains('ajax-submit')) {
            e.preventDefault();
            handleAjaxSubmit(e.target);
        }
    });
    
    // Handle auto-refresh toggle
    const autoRefreshToggle = document.getElementById('autoRefreshToggle');
    if (autoRefreshToggle) {
        autoRefreshToggle.addEventListener('change', function() {
            window.KeaDhcpApp.autoRefreshEnabled = this.checked;
            if (this.checked) {
                startAutoRefresh();
            } else {
                stopAutoRefresh();
            }
        });
    }
}

// Form validation setup
function setupFormValidation() {
    const forms = document.querySelectorAll('.needs-validation');
    
    forms.forEach(function(form) {
        form.addEventListener('submit', function(event) {
            if (!form.checkValidity()) {
                event.preventDefault();
                event.stopPropagation();
                showValidationErrors(form);
            }
            form.classList.add('was-validated');
        });
    });
}

// Show form loading state
function showFormLoading(form) {
    const submitBtn = form.querySelector('button[type="submit"]');
    if (submitBtn) {
        submitBtn.disabled = true;
        const originalText = submitBtn.innerHTML;
        submitBtn.innerHTML = '<i class="bi bi-hourglass-split"></i> Processing...';
        
        // Store original text for restoration
        submitBtn.dataset.originalText = originalText;
        
        // Set timeout to restore button if form doesn't redirect
        setTimeout(() => {
            if (submitBtn.dataset.originalText) {
                submitBtn.innerHTML = submitBtn.dataset.originalText;
                submitBtn.disabled = false;
            }
        }, 5000);
    }
}

// Show validation errors
function showValidationErrors(form) {
    const invalidInputs = form.querySelectorAll(':invalid');
    if (invalidInputs.length > 0) {
        invalidInputs[0].focus();
        showNotification('Please correct the highlighted errors', 'error');
    }
}

// Handle AJAX form submissions
function handleAjaxSubmit(element) {
    const form = element.closest('form');
    if (!form) return;
    
    const formData = new FormData(form);
    const url = form.action || window.location.href;
    const method = form.method || 'POST';
    
    fetch(url, {
        method: method,
        body: formData,
        headers: {
            'X-Requested-With': 'XMLHttpRequest'
        }
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showNotification(data.message || 'Operation completed successfully', 'success');
            if (data.reload) {
                setTimeout(() => window.location.reload(), 1000);
            }
        } else {
            showNotification(data.error || 'Operation failed', 'error');
        }
    })
    .catch(error => {
        console.error('AJAX error:', error);
        showNotification('An error occurred. Please try again.', 'error');
    });
}

// Show notifications
function showNotification(message, type = 'info') {
    const alertClass = type === 'error' ? 'alert-danger' : `alert-${type}`;
    const iconClass = getNotificationIcon(type);
    
    const notificationHtml = `
        <div class="alert ${alertClass} alert-dismissible fade show notification-alert" role="alert">
            <i class="bi ${iconClass}"></i> ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    `;
    
    // Find or create notification container
    let container = document.querySelector('.notification-container');
    if (!container) {
        container = document.createElement('div');
        container.className = 'notification-container position-fixed top-0 end-0 p-3';
        container.style.zIndex = '9999';
        document.body.appendChild(container);
    }
    
    container.insertAdjacentHTML('beforeend', notificationHtml);
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
        const alert = container.querySelector('.notification-alert:last-child');
        if (alert) {
            const bsAlert = new bootstrap.Alert(alert);
            bsAlert.close();
        }
    }, 5000);
}

// Get notification icon based on type
function getNotificationIcon(type) {
    switch (type) {
        case 'success': return 'bi-check-circle-fill';
        case 'error': return 'bi-exclamation-triangle-fill';
        case 'warning': return 'bi-exclamation-triangle-fill';
        case 'info': return 'bi-info-circle-fill';
        default: return 'bi-info-circle-fill';
    }
}

// Auto-refresh functionality
function startAutoRefresh() {
    if (window.KeaDhcpApp.statusUpdateInterval) {
        clearInterval(window.KeaDhcpApp.statusUpdateInterval);
    }
    
    if (window.KeaDhcpApp.autoRefreshEnabled) {
        window.KeaDhcpApp.statusUpdateInterval = setInterval(() => {
            updateServerStatus();
        }, window.KeaDhcpApp.refreshInterval);
    }
}

function stopAutoRefresh() {
    if (window.KeaDhcpApp.statusUpdateInterval) {
        clearInterval(window.KeaDhcpApp.statusUpdateInterval);
        window.KeaDhcpApp.statusUpdateInterval = null;
    }
}

// Update server status via AJAX
function updateServerStatus() {
    fetch('/api/status')
        .then(response => response.json())
        .then(data => {
            updateStatusIndicators(data);
        })
        .catch(error => {
            console.error('Status update failed:', error);
        });
}

// Update status indicators on page
function updateStatusIndicators(statusData) {
    // Update server status badge
    const statusBadge = document.querySelector('.server-status-badge');
    if (statusBadge && statusData.kea_status) {
        const isRunning = statusData.kea_status.status === 'running';
        statusBadge.className = `badge ${isRunning ? 'bg-success' : 'bg-danger'}`;
        statusBadge.innerHTML = `<i class="bi ${isRunning ? 'bi-check-circle-fill' : 'bi-x-circle-fill'}"></i> ${statusData.kea_status.status}`;
    }
    
    // Update active leases count
    const leasesCount = document.querySelector('.active-leases-count');
    if (leasesCount && statusData.active_leases !== undefined) {
        leasesCount.textContent = statusData.active_leases;
    }
    
    // Update uptime
    const uptimeDisplay = document.querySelector('.uptime-display');
    if (uptimeDisplay && statusData.uptime) {
        uptimeDisplay.textContent = formatUptime(statusData.uptime);
    }
}

// Format uptime seconds to human readable string
function formatUptime(seconds) {
    if (!seconds || seconds < 0) return 'Unknown';
    
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    
    if (days > 0) {
        return `${days}d ${hours}h ${minutes}m`;
    } else if (hours > 0) {
        return `${hours}h ${minutes}m`;
    } else {
        return `${minutes}m`;
    }
}

// Initialize data tables
function initializeDataTables() {
    const tables = document.querySelectorAll('.data-table');
    tables.forEach(table => {
        // Add sorting capability
        addTableSorting(table);
        
        // Add row highlighting
        addTableRowHighlighting(table);
    });
}

// Add table sorting functionality
function addTableSorting(table) {
    const headers = table.querySelectorAll('thead th');
    headers.forEach((header, index) => {
        if (!header.classList.contains('no-sort')) {
            header.style.cursor = 'pointer';
            header.addEventListener('click', () => sortTable(table, index));
            
            // Add sort indicator
            const sortIcon = document.createElement('i');
            sortIcon.className = 'bi bi-arrow-down-up ms-1 sort-icon';
            header.appendChild(sortIcon);
        }
    });
}

// Sort table by column
function sortTable(table, columnIndex) {
    const tbody = table.querySelector('tbody');
    const rows = Array.from(tbody.querySelectorAll('tr'));
    const header = table.querySelectorAll('thead th')[columnIndex];
    const isAscending = !header.classList.contains('sort-asc');
    
    // Clear all sort classes
    table.querySelectorAll('thead th').forEach(th => {
        th.classList.remove('sort-asc', 'sort-desc');
        const icon = th.querySelector('.sort-icon');
        if (icon) {
            icon.className = 'bi bi-arrow-down-up ms-1 sort-icon';
        }
    });
    
    // Set current sort class
    header.classList.add(isAscending ? 'sort-asc' : 'sort-desc');
    const icon = header.querySelector('.sort-icon');
    if (icon) {
        icon.className = `bi ${isAscending ? 'bi-arrow-up' : 'bi-arrow-down'} ms-1 sort-icon`;
    }
    
    // Sort rows
    rows.sort((a, b) => {
        const aVal = a.cells[columnIndex].textContent.trim();
        const bVal = b.cells[columnIndex].textContent.trim();
        
        // Try to parse as numbers
        const aNum = parseFloat(aVal);
        const bNum = parseFloat(bVal);
        
        if (!isNaN(aNum) && !isNaN(bNum)) {
            return isAscending ? aNum - bNum : bNum - aNum;
        } else {
            return isAscending ? aVal.localeCompare(bVal) : bVal.localeCompare(aVal);
        }
    });
    
    // Reorder rows in DOM
    rows.forEach(row => tbody.appendChild(row));
}

// Add table row highlighting
function addTableRowHighlighting(table) {
    const rows = table.querySelectorAll('tbody tr');
    rows.forEach(row => {
        row.addEventListener('mouseenter', function() {
            this.style.backgroundColor = '#f8f9fa';
        });
        
        row.addEventListener('mouseleave', function() {
            this.style.backgroundColor = '';
        });
    });
}

// IP Address validation
function validateIPAddress(ip) {
    const ipRegex = /^(\d{1,3}\.){3}\d{1,3}$/;
    if (!ipRegex.test(ip)) return false;
    
    const parts = ip.split('.');
    return parts.every(part => {
        const num = parseInt(part);
        return num >= 0 && num <= 255;
    });
}

// MAC Address validation
function validateMACAddress(mac) {
    const macPatterns = [
        /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/,  // xx:xx:xx:xx:xx:xx
        /^([0-9a-fA-F]{2}-){5}[0-9a-fA-F]{2}$/,  // xx-xx-xx-xx-xx-xx
        /^[0-9a-fA-F]{12}$/                        // xxxxxxxxxxxx
    ];
    
    return macPatterns.some(pattern => pattern.test(mac));
}

// Format MAC address
function formatMACAddress(mac) {
    // Remove any existing separators
    const cleanMac = mac.replace(/[^0-9a-fA-F]/g, '');
    
    // Format with colons
    return cleanMac.match(/.{2}/g)?.join(':').toLowerCase() || mac;
}

// Subnet utilities
function validateSubnetCIDR(subnet) {
    const parts = subnet.split('/');
    if (parts.length !== 2) return false;
    
    const ip = parts[0];
    const cidr = parseInt(parts[1]);
    
    return validateIPAddress(ip) && cidr >= 0 && cidr <= 32;
}

// Export utility functions to global scope
window.KeaDhcpUtils = {
    validateIPAddress,
    validateMACAddress,
    formatMACAddress,
    validateSubnetCIDR,
    showNotification,
    formatUptime
};

// Handle page unload
window.addEventListener('beforeunload', function() {
    stopAutoRefresh();
});

// Console welcome message
console.log('%c🌐 Kea DHCP Manager', 'color: #0d6efd; font-size: 16px; font-weight: bold;');
console.log('Application loaded successfully. Auto-refresh enabled.');
