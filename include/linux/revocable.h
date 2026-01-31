/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Revocable Resource Management
 *
 * Copyright 2025 Google LLC
 */

#ifndef __LINUX_REVOCABLE_H
#define __LINUX_REVOCABLE_H

#include <linux/types.h>

struct device;

/**
 * struct revocable_provider - Handle for a resource being provided
 * @resource: Pointer to the managed resource
 */
struct revocable_provider {
	void *resource;
};

/**
 * struct revocable - Handle for consuming a revocable resource
 * @provider: Pointer to the provider
 */
struct revocable {
	struct revocable_provider *provider;
};

/* Provider API */
struct revocable_provider *revocable_provider_alloc(void *resource);
struct revocable_provider *devm_revocable_provider_alloc(struct device *dev,
							 void *resource);
void revocable_provider_revoke(struct revocable_provider *provider);

/* Consumer API */
struct revocable *revocable_alloc(struct revocable_provider *provider);
void revocable_free(struct revocable *rev);
void *revocable_try_access(struct revocable *rev, int *idx);
void revocable_withdraw_access(struct revocable *rev, int idx);

/**
 * REVOCABLE_TRY_ACCESS_WITH - Convenience macro for revocable access
 * @rev: Consumer handle
 * @resource: Variable to store resource pointer
 * @code: Code to execute within access scope
 *
 * Automatically handles the access/withdraw cycle for accessing a
 * revocable resource. The @resource variable is set to the provider's
 * resource pointer or NULL if revoked.
 *
 * Example:
 *   REVOCABLE_TRY_ACCESS_WITH(rev, myres) {
 *       if (myres)
 *           do_something_with(myres);
 *   }
 */
#define REVOCABLE_TRY_ACCESS_WITH(rev, resource) \
	({ \
		int __idx; \
		void *resource = revocable_try_access(rev, &__idx); \
		(void)(__(&resource)); \
		if (true) { \
			__revocable_try_access_scoped_cleanup(__idx, rev); \
		} \
	})

#endif /* __LINUX_REVOCABLE_H */
