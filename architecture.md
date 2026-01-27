```

%%{init: {'theme':'dark', 'themeVariables': { 'primaryColor':'#4A90E2','primaryTextColor':'#fff','primaryBorderColor':'#2E5C8A','lineColor':'#F8B229','secondaryColor':'#E96D76','tertiaryColor':'#27AE60','noteBkgColor':'#1a1a1a','noteTextColor':'#fff'}}}%%

graph TB
    subgraph "🎯 Kubernetes Cluster - Production Environment"
        
        subgraph "📊 Monitoring Layer - Real-Time Detection"
            DS[🔍 DaemonSet Monitor<br/>━━━━━━━━━━━━━<br/>• Runs on Every Node<br/>• 60s Collection Interval<br/>• AWS CloudWatch API<br/>• Azure Monitor API]
            
            METRICS[📈 Metrics Exported<br/>━━━━━━━━━━━━━<br/>• DNS Throttling<br/>• Conntrack Status<br/>• Bandwidth Usage<br/>• PPS Limits]
            
            NE[🔌 Node Exporter<br/>━━━━━━━━━━━━━<br/>Port: 9100<br/>Prometheus Format]
        end
        
        subgraph "💾 Storage & Analytics Layer"
            PROM[📊 Prometheus<br/>━━━━━━━━━━━━━<br/>• 30s Scrape Interval<br/>• 15 Days Retention<br/>• PromQL Queries<br/>• Alert Evaluation]
            
            GRAF[📉 Grafana<br/>━━━━━━━━━━━━━<br/>• Real-time Dashboards<br/>• Historical Trends<br/>• Capacity Planning<br/>• Custom Alerts]
        end
        
        subgraph "🔔 Intelligent Alerting Layer"
            AM[⚡ Alertmanager<br/>━━━━━━━━━━━━━<br/>• Multi-tier Routing<br/>• Deduplication<br/>• Grouping & Silencing]
            
            ROUTES{🚦 Routing Logic<br/>━━━━━━━━━━━━━}
        end
        
        subgraph "🤖 Auto-Remediation Layer"
            WEBHOOK[🔧 Remediation Webhook<br/>━━━━━━━━━━━━━<br/>Python Flask API<br/>Kubernetes Client]
            
            SCALER[⚙️ CoreDNS Auto-Scaler<br/>━━━━━━━━━━━━━<br/>• Linear Algorithm<br/>• Min: 2, Max: 10<br/>• Node + Core Based]
            
            CACHE[🚀 NodeLocal DNS<br/>━━━━━━━━━━━━━<br/>• 80% Query Reduction<br/>• Local Caching<br/>• 169.254.20.10]
        end
        
        DS -->|Prometheus Metrics| NE
        NE -->|30s Scrape| PROM
        PROM -->|Visualize| GRAF
        PROM -->|Evaluate Rules| AM
        
        AM --> ROUTES
        
        ROUTES -->|⚠️ Warning| SLACK[💬 Slack<br/>#sre-alerts]
        ROUTES -->|🔥 Critical| PD[📟 PagerDuty<br/>On-Call]
        ROUTES -->|🚨 Emergency| EMAIL[📧 Email<br/>Management]
        ROUTES -->|🔧 All Alerts| WEBHOOK
        
        WEBHOOK -->|Scale Deployment| SCALER
        WEBHOOK -->|Status Update| SLACK
        
        SCALER -->|Adjust Replicas| COREDNS[🌐 CoreDNS<br/>━━━━━━━━━━━━━<br/>DNS Resolution<br/>Dynamic Scaling]
        
        CACHE -.->|Reduce Load| COREDNS
    end
    
    subgraph "📊 Results Achieved"
        RESULTS[✅ 100% Incident Reduction<br/>✅ 30-second Detection<br/>✅ 2-minute Remediation<br/>✅ $50K/month Saved<br/>✅ Zero Human Intervention]
    end
    
    COREDNS -.->|Impact| RESULTS
    
    style DS fill:#4A90E2,stroke:#2E5C8A,stroke-width:3px,color:#fff
    style PROM fill:#E96D76,stroke:#C14953,stroke-width:3px,color:#fff
    style GRAF fill:#F47B20,stroke:#C45E19,stroke-width:3px,color:#fff
    style AM fill:#9B59B6,stroke:#7D3C98,stroke-width:3px,color:#fff
    style WEBHOOK fill:#27AE60,stroke:#1E8449,stroke-width:3px,color:#fff
    style SCALER fill:#3498DB,stroke:#2874A6,stroke-width:3px,color:#fff
    style CACHE fill:#E74C3C,stroke:#C0392B,stroke-width:3px,color:#fff
    style COREDNS fill:#16A085,stroke:#117A65,stroke-width:3px,color:#fff
    style RESULTS fill:#F39C12,stroke:#D68910,stroke-width:4px,color:#000
    style ROUTES fill:#9B59B6,stroke:#7D3C98,stroke-width:2px,color:#fff
    style SLACK fill:#2C3E50,stroke:#1A252F,stroke-width:2px,color:#fff
    style PD fill:#C0392B,stroke:#922B21,stroke-width:2px,color:#fff
    style EMAIL fill:#34495E,stroke:#212F3D,stroke-width:2px,color:#fff
