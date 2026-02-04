// SPDX-License-Identifier: GPL-2.0
/*
 * Revocable Resource Management
 *
 * Provides a mechanism for safely managing resources that can be
 * asynchronously removed, such as those from hot-pluggable devices.
 * Uses a provider/consumer model built on Sleepable RCU (SRCU).
 *
 * Copyright 2025 Google LLC
 */

#include <linux/revocable.h>
#include <linux/device.h>
#include <linux/slab.h>
#include <linux/srcu.h>

static DEFINE_SRCU(revocable_srcu);

/**
 * revocable_provider_alloc - Allocate a revocable provider handle
 * @resource: Pointer to the resource being provided
 *
 * Allocates a new provider handle for a resource that may be asynchronously
 * removed. Returns a pointer to the allocated provider structure, or NULL
 * on allocation failure.
 */
struct revocable_provider *revocable_provider_alloc(void *resource)
{
	struct revocable_provider *provider;

	provider = kmalloc(sizeof(*provider), GFP_KERNEL);
	if (!provider)
		return NULL;

	provider->resource = resource;
	return provider;
}
EXPORT_SYMBOL_GPL(revocable_provider_alloc);

/**
 * devm_revocable_provider_alloc - Device-managed revocable provider allocation
 * @dev: Device managing the provider
 * @resource: Pointer to the resource being provided
 *
 * Allocates a provider handle with device-managed resource cleanup.
 * The provider will be automatically freed when the device is removed.
 */
struct revocable_provider *devm_revocable_provider_alloc(struct device *dev,
							 void *resource)
{
	struct revocable_provider *provider;

	provider = devm_kmalloc(dev, sizeof(*provider), GFP_KERNEL);
	if (!provider)
		return NULL;

	provider->resource = resource;
	return provider;
}
EXPORT_SYMBOL_GPL(devm_revocable_provider_alloc);

/**
 * revocable_provider_revoke - Revoke a provider's resource
 * @provider: Provider to revoke
 *
 * Marks the provider's resource as revoked and waits for all active
 * consumers to finish accessing it. After this function returns, no new
 * consumers can access the resource, and all existing accesses will
 * receive NULL.
 */
void revocable_provider_revoke(struct revocable_provider *provider)
{
	if (!provider)
		return;

	provider->resource = NULL;
	synchronize_srcu(&revocable_srcu);
}
EXPORT_SYMBOL_GPL(revocable_provider_revoke);

/**
 * revocable_alloc - Allocate a consumer handle
 * @provider: Provider to consume from
 *
 * Allocates a consumer handle for accessing a provider's resource.
 * Returns a pointer to the allocated consumer structure, or NULL
 * on allocation failure.
 */
struct revocable *revocable_alloc(struct revocable_provider *provider)
{
	struct revocable *rev;

	rev = kmalloc(sizeof(*rev), GFP_KERNEL);
	if (!rev)
		return NULL;

	rev->provider = provider;
	return rev;
}
EXPORT_SYMBOL_GPL(revocable_alloc);

/**
 * revocable_free - Release a consumer handle
 * @rev: Consumer handle to free
 *
 * Releases a previously allocated consumer handle.
 */
void revocable_free(struct revocable *rev)
{
	kfree(rev);
}
EXPORT_SYMBOL_GPL(revocable_free);

/**
 * revocable_try_access - Attempt to access a provider's resource
 * @rev: Consumer handle
 * @idx: Pointer to store SRCU index for later release
 *
 * Attempts to access the provider's resource. If successful, stores an SRCU
 * index in @idx that must later be passed to revocable_withdraw_access().
 * Returns the resource pointer if access succeeds, NULL if the resource
 * has been revoked.
 *
 * The caller must be prepared to handle NULL returns if revocation occurs
 * between the call and actual resource use.
 */
void *revocable_try_access(struct revocable *rev, int *idx)
{
	void *resource;

	if (!rev || !rev->provider)
		return NULL;

	*idx = srcu_read_lock(&revocable_srcu);
	resource = srcu_dereference(rev->provider->resource, &revocable_srcu);

	return resource;
}
EXPORT_SYMBOL_GPL(revocable_try_access);

/**
 * revocable_withdraw_access - Release SRCU read lock from revocable_try_access
 * @rev: Consumer handle
 * @idx: SRCU index from revocable_try_access()
 *
 * Must be called to release the SRCU read lock acquired by revocable_try_access().
 */
void revocable_withdraw_access(struct revocable *rev, int idx)
{
	srcu_read_unlock(&revocable_srcu, idx);
}
EXPORT_SYMBOL_GPL(revocable_withdraw_access);
