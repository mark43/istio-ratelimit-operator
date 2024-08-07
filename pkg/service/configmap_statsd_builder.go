package service

import (
	"fmt"
	"strings"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/zufardhiyaulhaq/istio-ratelimit-operator/api/v1alpha1"
	"github.com/zufardhiyaulhaq/istio-ratelimit-operator/pkg/types"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type StatsdConfigBuilder struct {
	Config           string
	RateLimitService v1alpha1.RateLimitService
}

func NewStatsdConfigBuilder() *StatsdConfigBuilder {
	return &StatsdConfigBuilder{}
}

func (n *StatsdConfigBuilder) SetRateLimitService(rateLimitService v1alpha1.RateLimitService) *StatsdConfigBuilder {
	n.RateLimitService = rateLimitService
	return n
}

func (n *StatsdConfigBuilder) SetConfig(config string) *StatsdConfigBuilder {
	n.Config = config
	return n
}

func (n *StatsdConfigBuilder) Build() (*corev1.ConfigMap, error) {
	configMap := &corev1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name:      n.RateLimitService.Name + "-statsd-config",
			Namespace: n.RateLimitService.Namespace,
			Labels:    n.BuildLabels(),
		},
		Data: map[string]string{
			"statsd.mappingConf": n.Config,
		},
	}

	return configMap, nil
}

func (n *StatsdConfigBuilder) BuildLabels() map[string]string {
	var labels = map[string]string{
		"app.kubernetes.io/name":       n.RateLimitService.Name + "-statsd-config",
		"app.kubernetes.io/managed-by": "istio-rateltimit-operator",
		"app.kubernetes.io/created-by": n.RateLimitService.Name,
	}

	return labels
}

func NewStatsdConfig(rateLimitServiceName string, globalRateLimitDomain string, globalRateLimitList []v1alpha1.GlobalRateLimit) (types.MetricMapper, error) {
	metricMapper := types.MetricMapper{}

	for _, globalRateLimit := range globalRateLimitList {
		if globalRateLimit.Spec.Identifier != nil {
			metricMappings, err := NewMetricMappingFromGlobalRateLimit(rateLimitServiceName, globalRateLimitDomain, globalRateLimit)
			if err != nil {
				return metricMapper, err
			}

			metricMapper.Mappings = append(metricMapper.Mappings, metricMappings...)
		}
	}

	metricMapper.Mappings = append(metricMapper.Mappings, NewDefaultMetricMapping()...)

	return metricMapper, nil
}

func NewMetricMappingFromGlobalRateLimit(rateLimitServiceName string, globalRateLimitDomain string, globalRateLimit v1alpha1.GlobalRateLimit) ([]types.MetricMapping, error) {
	metricMappings := []types.MetricMapping{}

	regexMatcher := NewStatsdRegexMatcherFromGlobalRateLimitMatcher(globalRateLimit.Spec.Matcher, globalRateLimit.Spec.DetailedMetric)

	var matchType string
	if globalRateLimit.Spec.DetailedMetric {
		matchType = "regex"
	} else {
		matchType = ""
	}

	// Near Limit
	nearLimitMetricValue, nearLimitDynamicMetricLabels := MatchString("ratelimit.service.rate_limit."+globalRateLimitDomain+"."+regexMatcher+".near_limit", globalRateLimit.Spec.DetailedMetric)
	nearLimitStaticMetricLabels := prometheus.Labels{
		"identifier":              *globalRateLimit.Spec.Identifier,
		"rate_limit_service_name": rateLimitServiceName,
		"global_rate_limit_name":  globalRateLimit.Name,
		"route":                   *globalRateLimit.Spec.Selector.Route,
	}
	nearLimitLabels := mergeMaps(nearLimitStaticMetricLabels, nearLimitDynamicMetricLabels)
	nearLimitMetricMapping := types.MetricMapping{
		Name:      "ratelimit_service_rate_limit_near_limit",
		Match:     nearLimitMetricValue,
		MatchType: matchType,
		TimerType: types.ObserverTypeHistogram,
		Labels:    nearLimitLabels,
	}

	// Over Limit
	overLimitMetricValue, overLimitDynamicMetricLabels := MatchString("ratelimit.service.rate_limit."+globalRateLimitDomain+"."+regexMatcher+".over_limit", globalRateLimit.Spec.DetailedMetric)
	overLimitStaticMetricLabels := prometheus.Labels{
		"identifier":              *globalRateLimit.Spec.Identifier,
		"rate_limit_service_name": rateLimitServiceName,
		"global_rate_limit_name":  globalRateLimit.Name,
		"route":                   *globalRateLimit.Spec.Selector.Route,
	}
	overLimitLabels := mergeMaps(overLimitStaticMetricLabels, overLimitDynamicMetricLabels)
	overLimitMetricMapping := types.MetricMapping{
		Name:      "ratelimit_service_rate_limit_over_limit",
		Match:     overLimitMetricValue,
		MatchType: matchType,
		TimerType: types.ObserverTypeHistogram,
		Labels:    overLimitLabels,
	}

	// Over Limit with local cache
	overLimitWithCacheMetricValue, overLimitWithCacheDynamicMetricLabels := MatchString("ratelimit.service.rate_limit."+globalRateLimitDomain+"."+regexMatcher+".over_limit_with_local_cache", globalRateLimit.Spec.DetailedMetric)
	overLimitWithCacheStaticMetricLabels := prometheus.Labels{
		"identifier":              *globalRateLimit.Spec.Identifier,
		"rate_limit_service_name": rateLimitServiceName,
		"global_rate_limit_name":  globalRateLimit.Name,
		"route":                   *globalRateLimit.Spec.Selector.Route,
	}
	overLimitWithCacheLabels := mergeMaps(overLimitWithCacheStaticMetricLabels, overLimitWithCacheDynamicMetricLabels)
	overLimitWithLocalCacheMetricMapping := types.MetricMapping{
		Name:      "ratelimit_service_rate_limit_over_limit_with_local_cache",
		Match:     overLimitWithCacheMetricValue,
		MatchType: matchType,
		TimerType: types.ObserverTypeHistogram,
		Labels:    overLimitWithCacheLabels,
	}

	// Total Hits

	totalHitsMetricValue, totalHitsDynamicMetricLabels := MatchString("ratelimit.service.rate_limit."+globalRateLimitDomain+"."+regexMatcher+".total_hits", globalRateLimit.Spec.DetailedMetric)
	totalHitsStaticMetricLabels := prometheus.Labels{
		"identifier":              *globalRateLimit.Spec.Identifier,
		"rate_limit_service_name": rateLimitServiceName,
		"global_rate_limit_name":  globalRateLimit.Name,
		"route":                   *globalRateLimit.Spec.Selector.Route,
	}
	totalHitsLabels := mergeMaps(totalHitsStaticMetricLabels, totalHitsDynamicMetricLabels)
	totalHitsMetricMapping := types.MetricMapping{
		Name:      "ratelimit_service_rate_limit_total_hits",
		Match:     totalHitsMetricValue,
		MatchType: matchType,
		TimerType: types.ObserverTypeHistogram,
		Labels:    totalHitsLabels,
	}

	// Within Limit
	withinLimitMetricValue, withinLimitDynamicMetricLabels := MatchString("ratelimit.service.rate_limit."+globalRateLimitDomain+"."+regexMatcher+".within_limit", globalRateLimit.Spec.DetailedMetric)
	withinLimitStaticMetricLabels := prometheus.Labels{
		"identifier":              *globalRateLimit.Spec.Identifier,
		"rate_limit_service_name": rateLimitServiceName,
		"global_rate_limit_name":  globalRateLimit.Name,
		"route":                   *globalRateLimit.Spec.Selector.Route,
	}
	withinLimitLabels := mergeMaps(withinLimitStaticMetricLabels, withinLimitDynamicMetricLabels)
	withinLimitMetricMapping := types.MetricMapping{
		Name:      "ratelimit_service_rate_limit_within_limit",
		Match:     withinLimitMetricValue,
		MatchType: matchType,
		TimerType: types.ObserverTypeHistogram,
		Labels:    withinLimitLabels,
	}

	// Shadow Mode
	shadowModeMetricValue, shadowModeDynamicMetricLabels := MatchString("ratelimit.service.rate_limit."+globalRateLimitDomain+"."+regexMatcher+".shadow_mode", globalRateLimit.Spec.DetailedMetric)
	shadowModeStaticMetricLabels := prometheus.Labels{
		"identifier":              *globalRateLimit.Spec.Identifier,
		"rate_limit_service_name": rateLimitServiceName,
		"global_rate_limit_name":  globalRateLimit.Name,
		"route":                   *globalRateLimit.Spec.Selector.Route,
	}
	shadowModeLabels := mergeMaps(shadowModeStaticMetricLabels, shadowModeDynamicMetricLabels)
	shadowModeMetricMapping := types.MetricMapping{
		Name:      "ratelimit_service_rate_limit_shadow_mode",
		Match:     shadowModeMetricValue,
		MatchType: matchType,
		TimerType: types.ObserverTypeHistogram,
		Labels:    shadowModeLabels,
	}

	metricMappings = append(metricMappings, nearLimitMetricMapping, overLimitMetricMapping, overLimitWithLocalCacheMetricMapping, totalHitsMetricMapping, withinLimitMetricMapping, shadowModeMetricMapping)

	return metricMappings, nil
}

func NewStatsdRegexMatcherFromGlobalRateLimitMatcher(matchers []*v1alpha1.GlobalRateLimit_Action, detailedMetric bool) string {
	var regex string

	matchersLength := len(matchers)
	for index, matcher := range matchers {
		if matcher.RequestHeaders != nil {
			regex = regex + matcher.RequestHeaders.DescriptorKey
		}

		if matcher.RemoteAddress != nil {
			regex = regex + "remote_address"
		}

		if matcher.GenericKey != nil {
			if matcher.GenericKey.DescriptorKey != nil {
				regex = regex + *matcher.GenericKey.DescriptorKey + "_" + matcher.GenericKey.DescriptorValue
			} else {
				regex = regex + "generic_key" + "_" + matcher.GenericKey.DescriptorValue
			}

		}

		if matcher.HeaderValueMatch != nil {
			regex = regex + "header_match" + "_" + matcher.HeaderValueMatch.DescriptorValue
		}

		if index+1 != matchersLength {
			regex = regex + "."
		}
	}

	return regex
}

func NewDefaultMetricMapping() []types.MetricMapping {
	return []types.MetricMapping{
		{
			Name:            "ratelimit_service_should_rate_limit_error",
			Match:           "ratelimit.service.call.should_rate_limit.*",
			MatchMetricType: types.MetricTypeCounter,
			Labels: prometheus.Labels{
				"err_type": "$1",
			},
		},
		{
			Name:            "ratelimit_service_total_requests",
			Match:           "ratelimit_server.*.total_requests",
			MatchMetricType: types.MetricTypeCounter,
			Labels: prometheus.Labels{
				"grpc_method": "$1",
			},
		},
		{
			Name:      "ratelimit_service_response_time_seconds",
			Match:     "ratelimit_server.*.response_time",
			TimerType: types.ObserverTypeHistogram,
			Labels: prometheus.Labels{
				"grpc_method": "$1",
			},
		},
		{
			Name:  "ratelimit_service_config_load_success",
			Match: "ratelimit.service.config_load_success",
		},
		{
			Name:  "ratelimit_service_config_load_error",
			Match: "ratelimit.service.config_load_error",
		},
		{
			Name:  "ratelimit_service_global_shadow_mode",
			Match: "ratelimit.service.global_shadow_mode",
		},
	}
}

func MatchString(matchString string, detailed_metric bool) (string, map[string]string) {
	var newMatchString string
	labels := make(map[string]string)
	//var response map[string]any

	if detailed_metric {
		parts := strings.Split(matchString, ".")
		//partsLen := len(parts)

		// Take the first four items (ratelimit.service.rate_limit.DOMAIN)
		firstFour := parts[:4]
		// Join them together with escaped delimiter
		prefix := strings.Join(firstFour, "\\\\.")

		// Loop over key_value parts excluding the first four
		var keyValue string
		for index, part := range parts[4:] {
			part := strings.Replace(part, "-", "_", -1)
			// Original index adjusted by 4 (because we skip first four elements)
			//originalIndex := index + 4
			// Regex match groups start at 1
			regexMatchGroup := index + 1
			// Check if last part as that's counter name
			isLast := index == len(parts)-5
			if isLast {
				keyValue += fmt.Sprintf("\\\\.%s", part)
			} else {
				keyValue += fmt.Sprintf("\\\\.%s_?(.*)", part)

				// Add additional labels
				labels[strings.Replace(part, "-", "_", -1)] = fmt.Sprintf("$%d", regexMatchGroup)
				// Add generic label
				labels["key"+fmt.Sprint(regexMatchGroup)] = fmt.Sprintf("$%d", regexMatchGroup)

			}
		}

		newMatchString = "\"" + prefix + keyValue + "\""
	} else {
		newMatchString = matchString
	}

	return newMatchString, labels

}

func mergeMaps(map1, map2 map[string]string) map[string]string {
	merged := make(map[string]string)

	// Add all key-value pairs from map1 to merged
	for key, value := range map1 {
		merged[key] = value
	}

	// Add all key-value pairs from map2 to merged
	// If the key exists, it will overwrite the value from map1
	for key, value := range map2 {
		merged[key] = value
	}

	return merged
}
