import React, { useState, useEffect } from 'react';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import { AlertCircle, TrendingUp, Package, Zap, Activity, Settings, LogOut } from 'lucide-react';

// Type definitions
interface TenantMetrics {
  tenantId: string;
  storageUsed: number;
  storageQuota: number;
  requestCount: number;
  bandwidthUsed: number;
  lastUpdated: string;
}

interface SystemMetrics {
  timestamp: string;
  errorRate: number;
  throughput: number;
  latencyP99: number;
  cacheHitRatio: number;
  replicationLag: number;
}

interface Alert {
  id: string;
  severity: 'critical' | 'warning' | 'info';
  message: string;
  timestamp: string;
}

interface DashboardState {
  tenants: TenantMetrics[];
  systemMetrics: SystemMetrics[];
  alerts: Alert[];
  selectedTenant: string | null;
  loading: boolean;
}

// Main Dashboard Component
const EnterpriseMinIODashboard: React.FC = () => {
  const [state, setState] = useState<DashboardState>({
    tenants: [],
    systemMetrics: [],
    alerts: [],
    selectedTenant: null,
    loading: true,
  });

  const [timeRange, setTimeRange] = useState<'1h' | '24h' | '7d'>('1h');
  const [refreshInterval, setRefreshInterval] = useState<number>(5000);

  // Fetch metrics on mount and interval
  useEffect(() => {
    const fetchMetrics = async () => {
      try {
        const [tenantsRes, metricsRes, alertsRes] = await Promise.all([
          fetch(`/api/tenants?timeRange=${timeRange}`),
          fetch(`/api/metrics?timeRange=${timeRange}`),
          fetch('/api/alerts?limit=10'),
        ]);

        const tenants = await tenantsRes.json();
        const metrics = await metricsRes.json();
        const alerts = await alertsRes.json();

        setState((prev) => ({
          ...prev,
          tenants,
          systemMetrics: metrics,
          alerts,
          loading: false,
        }));
      } catch (error) {
        console.error('Failed to fetch metrics:', error);
        setState((prev) => ({ ...prev, loading: false }));
      }
    };

    fetchMetrics();
    const interval = setInterval(fetchMetrics, refreshInterval);
    return () => clearInterval(interval);
  }, [timeRange, refreshInterval]);

  if (state.loading) {
    return <LoadingScreen />;
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 to-slate-800">
      <Header />
      
      <div className="max-w-7xl mx-auto px-4 py-8">
        {/* Top Alert Bar */}
        {state.alerts.length > 0 && <AlertBanner alerts={state.alerts} />}

        {/* Navigation and Controls */}
        <div className="flex justify-between items-center mb-8">
          <div>
            <h1 className="text-3xl font-bold text-white mb-2">
              Enterprise MinIO Control Panel
            </h1>
            <p className="text-slate-400">Real-time monitoring and management</p>
          </div>

          <div className="flex gap-4">
            <TimeRangeSelector value={timeRange} onChange={setTimeRange} />
            <RefreshControl interval={refreshInterval} onIntervalChange={setRefreshInterval} />
          </div>
        </div>

        {/* Key Metrics Cards */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
          <MetricCard
            title="Total Storage"
            value={`${(state.tenants.reduce((sum, t) => sum + t.storageUsed, 0) / 1e12).toFixed(2)} TB`}
            icon={<Package className="w-6 h-6" />}
            trend="+12.5%"
            color="from-blue-500 to-blue-600"
          />
          <MetricCard
            title="Throughput"
            value={`${state.systemMetrics[state.systemMetrics.length - 1]?.throughput.toFixed(0) || 0} ops/sec`}
            icon={<Zap className="w-6 h-6" />}
            trend="+8.2%"
            color="from-green-500 to-green-600"
          />
          <MetricCard
            title="Error Rate"
            value={`${state.systemMetrics[state.systemMetrics.length - 1]?.errorRate.toFixed(2) || 0}%`}
            icon={<AlertCircle className="w-6 h-6" />}
            trend="-2.1%"
            color="from-red-500 to-red-600"
          />
          <MetricCard
            title="Cache Hit Ratio"
            value={`${(state.systemMetrics[state.systemMetrics.length - 1]?.cacheHitRatio * 100 || 0).toFixed(1)}%`}
            icon={<Activity className="w-6 h-6" />}
            trend="+5.3%"
            color="from-purple-500 to-purple-600"
          />
        </div>

        {/* Performance Charts */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <PerformanceChart
            title="Throughput Over Time"
            data={state.systemMetrics}
            dataKey="throughput"
            color="#10b981"
          />
          <LatencyChart
            title="Request Latency Percentiles"
            data={state.systemMetrics}
            color="#3b82f6"
          />
        </div>

        {/* Tenant Management and Replication */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
          <div className="lg:col-span-2">
            <TenantList
              tenants={state.tenants}
              selectedTenant={state.selectedTenant}
              onSelectTenant={(id) => setState((prev) => ({ ...prev, selectedTenant: id }))}
            />
          </div>
          <ReplicationStatus />
        </div>

        {/* Detailed Metrics */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <CacheMetricsChart data={state.systemMetrics} />
          <StorageDistributionChart tenants={state.tenants} />
        </div>
      </div>
    </div>
  );
};

// ===== Component Library =====

const Header: React.FC = () => (
  <header className="bg-slate-900/50 backdrop-blur border-b border-slate-700">
    <div className="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 bg-gradient-to-br from-orange-400 to-orange-600 rounded-lg flex items-center justify-center">
          <span className="text-white font-bold">M</span>
        </div>
        <span className="text-xl font-bold text-white">Enterprise MinIO</span>
      </div>

      <nav className="flex items-center gap-6">
        <button className="text-slate-300 hover:text-white transition flex items-center gap-2">
          <Settings className="w-5 h-5" />
          Settings
        </button>
        <button className="text-slate-300 hover:text-white transition flex items-center gap-2">
          <LogOut className="w-5 h-5" />
          Logout
        </button>
      </nav>
    </div>
  </header>
);

interface AlertBannerProps {
  alerts: Alert[];
}

const AlertBanner: React.FC<AlertBannerProps> = ({ alerts }) => {
  const critical = alerts.filter((a) => a.severity === 'critical');

  return (
    <div className="mb-6 p-4 bg-red-900/20 border border-red-500/50 rounded-lg">
      <div className="flex items-start gap-3">
        <AlertCircle className="w-6 h-6 text-red-500 mt-0.5 flex-shrink-0" />
        <div>
          <h3 className="text-red-200 font-semibold mb-2">
            {critical.length} Critical Alert{critical.length !== 1 ? 's' : ''}
          </h3>
          <ul className="space-y-1">
            {critical.slice(0, 3).map((alert) => (
              <li key={alert.id} className="text-red-100 text-sm">
                {alert.message}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
};

interface TimeRangeSelectorProps {
  value: '1h' | '24h' | '7d';
  onChange: (value: '1h' | '24h' | '7d') => void;
}

const TimeRangeSelector: React.FC<TimeRangeSelectorProps> = ({ value, onChange }) => (
  <div className="flex gap-2 bg-slate-800 p-1 rounded-lg">
    {(['1h', '24h', '7d'] as const).map((range) => (
      <button
        key={range}
        onClick={() => onChange(range)}
        className={`px-4 py-2 rounded transition ${
          value === range
            ? 'bg-orange-500 text-white'
            : 'text-slate-300 hover:text-white'
        }`}
      >
        {range.toUpperCase()}
      </button>
    ))}
  </div>
);

interface RefreshControlProps {
  interval: number;
  onIntervalChange: (interval: number) => void;
}

const RefreshControl: React.FC<RefreshControlProps> = ({ interval, onIntervalChange }) => (
  <select
    value={interval}
    onChange={(e) => onIntervalChange(Number(e.target.value))}
    className="bg-slate-800 text-white px-4 py-2 rounded border border-slate-700 hover:border-slate-600 cursor-pointer"
  >
    <option value={1000}>Every 1s</option>
    <option value={5000}>Every 5s</option>
    <option value={10000}>Every 10s</option>
    <option value={30000}>Every 30s</option>
  </select>
);

interface MetricCardProps {
  title: string;
  value: string;
  icon: React.ReactNode;
  trend: string;
  color: string;
}

const MetricCard: React.FC<MetricCardProps> = ({ title, value, icon, trend, color }) => (
  <div className={`bg-gradient-to-br ${color} p-6 rounded-lg text-white`}>
    <div className="flex justify-between items-start mb-4">
      <div className="opacity-90">{icon}</div>
      <span className="text-sm text-green-200 flex items-center gap-1">
        <TrendingUp className="w-4 h-4" />
        {trend}
      </span>
    </div>
    <h3 className="text-sm font-medium opacity-90 mb-1">{title}</h3>
    <p className="text-2xl font-bold">{value}</p>
  </div>
);

interface PerformanceChartProps {
  title: string;
  data: SystemMetrics[];
  dataKey: keyof SystemMetrics;
  color: string;
}

const PerformanceChart: React.FC<PerformanceChartProps> = ({ title, data, dataKey, color }) => (
  <div className="bg-slate-800/50 backdrop-blur border border-slate-700 rounded-lg p-6">
    <h3 className="text-white font-semibold mb-4">{title}</h3>
    <ResponsiveContainer width="100%" height={300}>
      <LineChart data={data}>
        <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
        <XAxis dataKey="timestamp" stroke="#9ca3af" style={{ fontSize: '12px' }} />
        <YAxis stroke="#9ca3af" style={{ fontSize: '12px' }} />
        <Tooltip
          contentStyle={{
            backgroundColor: '#1e293b',
            border: '1px solid #475569',
            borderRadius: '8px',
          }}
          labelStyle={{ color: '#e2e8f0' }}
        />
        <Line
          type="monotone"
          dataKey={dataKey}
          stroke={color}
          dot={false}
          strokeWidth={2}
          isAnimationActive={false}
        />
      </LineChart>
    </ResponsiveContainer>
  </div>
);

interface LatencyChartProps {
  title: string;
  data: SystemMetrics[];
  color: string;
}

const LatencyChart: React.FC<LatencyChartProps> = ({ title, data, color }) => (
  <div className="bg-slate-800/50 backdrop-blur border border-slate-700 rounded-lg p-6">
    <h3 className="text-white font-semibold mb-4">{title}</h3>
    <ResponsiveContainer width="100%" height={300}>
      <BarChart data={data}>
        <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
        <XAxis dataKey="timestamp" stroke="#9ca3af" style={{ fontSize: '12px' }} />
        <YAxis stroke="#9ca3af" style={{ fontSize: '12px' }} />
        <Tooltip
          contentStyle={{
            backgroundColor: '#1e293b',
            border: '1px solid #475569',
            borderRadius: '8px',
          }}
          labelStyle={{ color: '#e2e8f0' }}
        />
        <Bar dataKey="latencyP99" fill={color} radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  </div>
);

interface TenantListProps {
  tenants: TenantMetrics[];
  selectedTenant: string | null;
  onSelectTenant: (id: string) => void;
}

const TenantList: React.FC<TenantListProps> = ({ tenants, selectedTenant, onSelectTenant }) => (
  <div className="bg-slate-800/50 backdrop-blur border border-slate-700 rounded-lg p-6">
    <h3 className="text-white font-semibold mb-4">Active Tenants</h3>
    <div className="space-y-3 max-h-96 overflow-y-auto">
      {tenants.map((tenant) => {
        const percentUsed = (tenant.storageUsed / tenant.storageQuota) * 100;
        const isSelected = selectedTenant === tenant.tenantId;

        return (
          <div
            key={tenant.tenantId}
            onClick={() => onSelectTenant(tenant.tenantId)}
            className={`p-4 rounded-lg cursor-pointer transition border-2 ${
              isSelected
                ? 'bg-orange-500/20 border-orange-500'
                : 'bg-slate-700/30 border-slate-600 hover:border-slate-500'
            }`}
          >
            <div className="flex justify-between items-start mb-2">
              <span className="text-white font-medium">{tenant.tenantId}</span>
              <span className="text-xs text-slate-400">{tenant.requestCount} requests</span>
            </div>
            <div className="mb-2">
              <div className="flex justify-between text-xs text-slate-300 mb-1">
                <span>Storage</span>
                <span>{percentUsed.toFixed(1)}%</span>
              </div>
              <div className="w-full bg-slate-700 rounded-full h-2 overflow-hidden">
                <div
                  className="bg-gradient-to-r from-blue-500 to-blue-600 h-full"
                  style={{ width: `${Math.min(percentUsed, 100)}%` }}
                />
              </div>
            </div>
            <div className="text-xs text-slate-400">
              {(tenant.storageUsed / 1e9).toFixed(2)} GB / {(tenant.storageQuota / 1e9).toFixed(2)} GB
            </div>
          </div>
        );
      })}
    </div>
  </div>
);

const ReplicationStatus: React.FC = () => (
  <div className="bg-slate-800/50 backdrop-blur border border-slate-700 rounded-lg p-6">
    <h3 className="text-white font-semibold mb-4">Replication Status</h3>
    <div className="space-y-3">
      {[
        { region: 'us-east-1', status: 'healthy', lag: '45ms' },
        { region: 'eu-west-1', status: 'healthy', lag: '120ms' },
        { region: 'ap-southeast-1', status: 'degraded', lag: '850ms' },
      ].map((region) => (
        <div key={region.region} className="flex items-center justify-between p-3 bg-slate-700/30 rounded">
          <div>
            <p className="text-white font-medium text-sm">{region.region}</p>
            <p className={`text-xs ${region.status === 'healthy' ? 'text-green-400' : 'text-yellow-400'}`}>
              {region.status}
            </p>
          </div>
          <span className="text-slate-400 text-sm">{region.lag}</span>
        </div>
      ))}
    </div>
  </div>
);

const CacheMetricsChart: React.FC<{ data: SystemMetrics[] }> = ({ data }) => (
  <div className="bg-slate-800/50 backdrop-blur border border-slate-700 rounded-lg p-6">
    <h3 className="text-white font-semibold mb-4">Cache Performance</h3>
    <ResponsiveContainer width="100%" height={300}>
      <LineChart data={data}>
        <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
        <XAxis dataKey="timestamp" stroke="#9ca3af" style={{ fontSize: '12px' }} />
        <YAxis stroke="#9ca3af" style={{ fontSize: '12px' }} />
        <Tooltip
          contentStyle={{
            backgroundColor: '#1e293b',
            border: '1px solid #475569',
            borderRadius: '8px',
          }}
          labelStyle={{ color: '#e2e8f0' }}
        />
        <Legend wrapperStyle={{ color: '#9ca3af' }} />
        <Line type="monotone" dataKey="cacheHitRatio" stroke="#8b5cf6" name="Hit Ratio" />
      </LineChart>
    </ResponsiveContainer>
  </div>
);

const StorageDistributionChart: React.FC<{ tenants: TenantMetrics[] }> = ({ tenants }) => {
  const data = tenants.map((t) => ({
    name: t.tenantId.substring(0, 8),
    value: t.storageUsed,
  }));

  const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6'];

  return (
    <div className="bg-slate-800/50 backdrop-blur border border-slate-700 rounded-lg p-6">
      <h3 className="text-white font-semibold mb-4">Storage Distribution</h3>
      <ResponsiveContainer width="100%" height={300}>
        <PieChart>
          <Pie
            data={data}
            cx="50%"
            cy="50%"
            labelLine={false}
            label={({ name, value }) => `${name}: ${(value / 1e9).toFixed(1)}GB`}
            outerRadius={80}
            fill="#8884d8"
            dataKey="value"
          >
            {data.map((entry, index) => (
              <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
            ))}
          </Pie>
          <Tooltip
            contentStyle={{
              backgroundColor: '#1e293b',
              border: '1px solid #475569',
              borderRadius: '8px',
            }}
            labelStyle={{ color: '#e2e8f0' }}
          />
        </PieChart>
      </ResponsiveContainer>
    </div>
  );
};

const LoadingScreen: React.FC = () => (
  <div className="min-h-screen bg-gradient-to-br from-slate-900 to-slate-800 flex items-center justify-center">
    <div className="text-center">
      <div className="animate-spin w-16 h-16 border-4 border-slate-700 border-t-orange-500 rounded-full mx-auto mb-4" />
      <p className="text-slate-300">Loading metrics...</p>
    </div>
  </div>
);

export default EnterpriseMinIODashboard;
